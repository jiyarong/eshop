"""
Full WB API docs scraper - visits all 11 doc sections and extracts complete content.
"""
import asyncio
import json
import re
from pathlib import Path
from playwright.async_api import async_playwright
from playwright_stealth import Stealth

BASE_URL = "https://dev.wildberries.ru"
OUT_DIR = Path(__file__).parent
stealth_obj = Stealth()

# All main documentation pages discovered
DOC_PAGES = [
    ("api-information",          "/docs/openapi/api-information"),
    ("work-with-products",       "/docs/openapi/work-with-products"),
    ("orders-fbs",               "/docs/openapi/orders-fbs"),
    ("orders-dbs",               "/docs/openapi/orders-dbs"),
    ("orders-fbw",               "/docs/openapi/orders-fbw"),
    ("in-store-pickup",          "/docs/openapi/in-store-pickup"),
    ("promotion",                "/docs/openapi/promotion"),
    ("analytics",                "/docs/openapi/analytics"),
    ("reports",                  "/docs/openapi/reports"),
    ("user-communication",       "/docs/openapi/user-communication"),
    ("financial-reports",        "/docs/openapi/financial-reports-and-accounting"),
]


async def goto_bypass(page, url: str) -> bool:
    await page.goto(url, wait_until="domcontentloaded", timeout=60000)
    title = await page.title()
    if "Почти готово" in title or "Almost ready" in title:
        try:
            await page.wait_for_function(
                "() => !document.title.includes('Почти готово') && !document.title.includes('Almost ready')",
                timeout=30000
            )
        except Exception as e:
            title = await page.title()
            if "Почти готово" in title:
                return False
    await asyncio.sleep(2)
    return True


async def scroll_and_expand(page):
    """Scroll down slowly to trigger lazy loading of API endpoint content."""
    # Scroll to bottom in steps
    await page.evaluate("""
        async () => {
            const distance = 800;
            const delay = 200;
            const scrollHeight = document.body.scrollHeight;
            let current = 0;
            while (current < scrollHeight) {
                window.scrollBy(0, distance);
                current += distance;
                await new Promise(r => setTimeout(r, delay));
            }
            // Scroll back up
            window.scrollTo(0, 0);
            await new Promise(r => setTimeout(r, 500));
        }
    """)
    await asyncio.sleep(1)


async def expand_all_sections(page):
    """Click all expand/collapse buttons to reveal full API details."""
    expanded = await page.evaluate("""
        async () => {
            let count = 0;
            // Find expand buttons in OpenAPI renderer (Redoc/Swagger style)
            const btns = document.querySelectorAll(
                'button[aria-expanded="false"], ' +
                '[class*="expand"], ' +
                '[class*="toggle"], ' +
                'summary, ' +
                '[class*="arrow"][class*="down"], ' +
                '[class*="chevron"]'
            );
            for (const btn of btns) {
                try {
                    btn.click();
                    count++;
                    await new Promise(r => setTimeout(r, 50));
                } catch(e) {}
            }
            return count;
        }
    """)
    await asyncio.sleep(1)


async def extract_full_content(page) -> dict:
    """Extract comprehensive API documentation from page."""
    return await page.evaluate("""
        () => {
            const data = {
                title: document.title,
                url: window.location.href,
                headings: {},
                endpoints: [],
                schemas: [],
                fullText: '',
            };

            // Extract headings
            ['h1','h2','h3','h4'].forEach(tag => {
                data.headings[tag] = Array.from(document.querySelectorAll(tag))
                    .map(h => h.innerText.trim())
                    .filter(t => t.length > 0);
            });

            // Find API operation blocks
            // Redoc uses data-section-id with operation ids
            const opSelectors = [
                '[data-section-id]',
                '[id^="tag/"]',
                '[id*="operation"]',
                '[id*="paths"]',
                '[class*="operation"]',
                '[class*="http-verb"]',
            ];

            const seenIds = new Set();
            opSelectors.forEach(sel => {
                document.querySelectorAll(sel).forEach(el => {
                    const id = el.id || el.getAttribute('data-section-id') || '';
                    if (!seenIds.has(id)) {
                        seenIds.add(id);
                        const text = el.innerText.trim();
                        if (text.length > 10) {
                            data.endpoints.push({
                                id,
                                text: text.substring(0, 5000),
                            });
                        }
                    }
                });
            });

            // Extract all text from main content area
            const contentSelectors = [
                '[class*="content"]',
                'main',
                'article',
                '#root',
                '.redoc-wrap',
            ];
            let mainEl = null;
            for (const sel of contentSelectors) {
                mainEl = document.querySelector(sel);
                if (mainEl && mainEl.innerText.length > 500) break;
            }
            if (!mainEl) mainEl = document.body;
            data.fullText = mainEl.innerText;

            return data;
        }
    """)


async def scrape_all():
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=True,
            args=['--no-sandbox', '--disable-blink-features=AutomationControlled', '--disable-dev-shm-usage'],
        )
        context = await browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            viewport={'width': 1920, 'height': 1080},
            locale='ru-RU',
            timezone_id='Europe/Moscow',
        )
        page = await context.new_page()
        await stealth_obj.apply_stealth_async(page)

        all_data = {}

        for i, (name, path) in enumerate(DOC_PAGES):
            url = f"{BASE_URL}{path}"
            print(f"\n[{i+1}/{len(DOC_PAGES)}] {name}")
            print(f"  URL: {url}")

            ok = await goto_bypass(page, url)
            if not ok:
                print(f"  FAILED to load")
                continue

            title = await page.title()
            print(f"  Title: {title}")

            # Scroll to trigger lazy loading
            await scroll_and_expand(page)
            # Try expanding all collapsed sections
            await expand_all_sections(page)
            # One more scroll pass
            await scroll_and_expand(page)

            content = await extract_full_content(page)
            all_data[name] = content

            text_len = len(content['fullText'])
            ep_count = len(content['endpoints'])
            h2_count = len(content['headings'].get('h2', []))
            print(f"  Content: {text_len} chars, {ep_count} endpoint blocks, {h2_count} h2 sections")
            print(f"  H2 headings: {content['headings'].get('h2', [])[:5]}")

            # Save individual page
            out_file = OUT_DIR / f"raw_{name}.json"
            with open(out_file, 'w', encoding='utf-8') as f:
                json.dump(content, f, ensure_ascii=False, indent=2)
            print(f"  Saved to {out_file.name}")

            await asyncio.sleep(0.5)

        # Save combined
        with open(OUT_DIR / 'all_raw.json', 'w', encoding='utf-8') as f:
            json.dump(all_data, f, ensure_ascii=False, indent=2)

        await browser.close()
        print(f"\n\nDone! Scraped {len(all_data)} pages.")


if __name__ == '__main__':
    asyncio.run(scrape_all())
