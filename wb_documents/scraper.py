"""
WB API docs scraper with stealth mode to bypass anti-bot protection.
Scrapes all API documentation from dev.wildberries.ru
"""
import asyncio
import json
import re
import time
from pathlib import Path
from playwright.async_api import async_playwright
from playwright_stealth import Stealth

BASE_URL = "https://dev.wildberries.ru"
DOCS_BASE = f"{BASE_URL}/docs/openapi"
OUT_DIR = Path(__file__).parent

stealth = Stealth()


async def bypass_challenge(page, url: str, timeout: int = 30000) -> bool:
    """Navigate to URL and wait for anti-bot challenge to complete."""
    await page.goto(url, wait_until="domcontentloaded", timeout=60000)
    title = await page.title()
    if "Почти готово" in title or "Almost ready" in title:
        print(f"  Anti-bot challenge detected, waiting...")
        try:
            await page.wait_for_function(
                "() => !document.title.includes('Почти готово') && !document.title.includes('Almost ready')",
                timeout=timeout
            )
            # Don't wait for networkidle - just a short pause
            await asyncio.sleep(2)
        except Exception as e:
            # Even if wait times out, check if title changed
            title = await page.title()
            if "Почти готово" in title or "Almost ready" in title:
                print(f"  Challenge not resolved: {e}")
                return False
            print(f"  Warning (continuing anyway): {e}")
    return True


async def inspect_nav(page) -> dict:
    """Inspect navigation structure in detail."""
    return await page.evaluate("""
        () => {
            const result = {
                allLinks: [],
                navStructure: [],
                sidebarHTML: '',
            };

            // Get all a tags with href containing /docs
            document.querySelectorAll('a[href]').forEach(a => {
                const href = a.getAttribute('href');
                const text = a.innerText.trim();
                if (href && (href.includes('/docs') || href.startsWith('/'))) {
                    result.allLinks.push({ href, text });
                }
            });

            // Find sidebar / nav
            const navSelectors = ['nav', '.sidebar', 'aside', '[class*="sidebar"]',
                                   '[class*="nav"]', '[class*="menu"]'];
            for (const sel of navSelectors) {
                const el = document.querySelector(sel);
                if (el) {
                    result.sidebarHTML = el.outerHTML.substring(0, 3000);
                    break;
                }
            }

            // Get page structure
            const structure = [];
            document.querySelectorAll('h1, h2, h3, [class*="section"], [class*="group"]').forEach(el => {
                structure.push({
                    tag: el.tagName,
                    class: el.className,
                    text: el.innerText.trim().substring(0, 100),
                });
            });
            result.navStructure = structure.slice(0, 50);

            return result;
        }
    """)


async def get_all_doc_links(page) -> list:
    """Extract all documentation page links from the sidebar."""
    return await page.evaluate("""
        () => {
            const links = new Map();

            // Try to find navigation with all sub-pages
            document.querySelectorAll('a[href]').forEach(a => {
                const href = a.getAttribute('href');
                const text = (a.innerText || a.textContent || '').trim();
                // Filter for doc links
                if (href && href.includes('/docs/openapi')) {
                    links.set(href, text);
                }
            });

            // Also check for data-href or similar attributes
            document.querySelectorAll('[data-href]').forEach(el => {
                const href = el.getAttribute('data-href');
                const text = (el.innerText || el.textContent || '').trim();
                if (href && href.includes('/docs/openapi')) {
                    links.set(href, text);
                }
            });

            return Array.from(links.entries()).map(([href, text]) => ({ href, text }));
        }
    """)


async def extract_api_content(page) -> dict:
    """Extract full API documentation from current page."""
    return await page.evaluate("""
        () => {
            const data = {
                title: document.title,
                url: window.location.href,
                h1: [],
                h2: [],
                h3: [],
                endpoints: [],
                fullText: '',
                tables: [],
            };

            // Headings
            document.querySelectorAll('h1').forEach(h => data.h1.push(h.innerText.trim()));
            document.querySelectorAll('h2').forEach(h => data.h2.push(h.innerText.trim()));
            document.querySelectorAll('h3').forEach(h => data.h3.push(h.innerText.trim()));

            // Look for API endpoint blocks (OpenAPI rendered)
            const endpointSelectors = [
                '[class*="operation"]',
                '[class*="endpoint"]',
                '[class*="method"]',
                '[class*="api"]',
                'section',
                'article',
            ];

            const seen = new Set();
            endpointSelectors.forEach(sel => {
                document.querySelectorAll(sel).forEach(el => {
                    const text = el.innerText.trim();
                    if (text.length > 30 && !seen.has(text.substring(0, 50))) {
                        seen.add(text.substring(0, 50));
                        // Try to identify HTTP method
                        const methodMatch = text.match(/^(GET|POST|PUT|DELETE|PATCH)/m);
                        data.endpoints.push({
                            text: text.substring(0, 2000),
                            method: methodMatch ? methodMatch[0] : null,
                        });
                    }
                });
            });

            // Tables (request/response schemas)
            document.querySelectorAll('table').forEach(table => {
                const rows = [];
                table.querySelectorAll('tr').forEach(tr => {
                    const cells = Array.from(tr.querySelectorAll('th, td')).map(
                        td => td.innerText.trim()
                    );
                    if (cells.length > 0) rows.push(cells);
                });
                if (rows.length > 0) data.tables.push(rows);
            });

            // Full text of main content
            const main = document.querySelector('main') ||
                          document.querySelector('[class*="content"]') ||
                          document.body;
            data.fullText = main.innerText.substring(0, 80000);

            return data;
        }
    """)


async def expand_all_nav_items(page):
    """Try to expand all collapsed nav items to reveal sub-pages."""
    await page.evaluate("""
        async () => {
            // Click all expandable nav items
            const clickables = document.querySelectorAll(
                '[class*="nav"] [class*="arrow"], ' +
                '[class*="nav"] [class*="toggle"], ' +
                '[class*="nav"] [class*="expand"], ' +
                '[class*="nav"] [class*="chevron"], ' +
                '[class*="sidebar"] button, ' +
                '[class*="sidebar"] [class*="toggle"]'
            );
            for (const el of clickables) {
                try { el.click(); } catch(e) {}
                await new Promise(r => setTimeout(r, 100));
            }
        }
    """)
    await asyncio.sleep(1)


async def scrape_all_docs():
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=True,
            args=[
                '--no-sandbox',
                '--disable-blink-features=AutomationControlled',
                '--disable-dev-shm-usage',
            ]
        )

        context = await browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            viewport={'width': 1920, 'height': 1080},
            locale='ru-RU',
            timezone_id='Europe/Moscow',
        )

        page = await context.new_page()
        await stealth.apply_stealth_async(page)

        print("=" * 60)
        print("Step 1: Visiting main page, bypassing anti-bot...")
        ok = await bypass_challenge(page, f"{DOCS_BASE}/api-information")
        if not ok:
            print("FAILED: Could not bypass anti-bot")
            await browser.close()
            return

        print(f"  Title: {await page.title()}")
        await page.screenshot(path=str(OUT_DIR / "screenshot_main.png"))

        # Inspect nav structure
        print("\nStep 2: Inspecting navigation structure...")
        nav_info = await inspect_nav(page)
        with open(OUT_DIR / 'nav_debug.json', 'w', encoding='utf-8') as f:
            json.dump(nav_info, f, ensure_ascii=False, indent=2)
        print(f"  Found {len(nav_info['allLinks'])} links on page")
        print("  Nav HTML preview:")
        print(nav_info['sidebarHTML'][:500])
        print("\n  All links found:")
        for lnk in nav_info['allLinks'][:30]:
            print(f"    {lnk['href']} -> {lnk['text'][:50]}")

        # Expand nav and get all links
        await expand_all_nav_items(page)
        doc_links = await get_all_doc_links(page)
        print(f"\n  After expanding: {len(doc_links)} doc links")

        # Save what we have so far
        with open(OUT_DIR / 'doc_links.json', 'w', encoding='utf-8') as f:
            json.dump(doc_links, f, ensure_ascii=False, indent=2)

        # Extract main page content
        print("\nStep 3: Extracting page content...")
        all_pages = {}
        content = await extract_api_content(page)
        all_pages['api-information'] = content
        print(f"  api-information: {len(content['fullText'])} chars, {len(content['h2'])} h2 headings")

        # Visit each doc link
        visited = {f"{DOCS_BASE}/api-information"}
        to_visit = [(lnk['href'], lnk['text']) for lnk in doc_links
                    if lnk['href'] not in visited]

        print(f"\nStep 4: Visiting {len(to_visit)} additional pages...")
        for i, (href, text) in enumerate(to_visit):
            url = f"{BASE_URL}{href}" if href.startswith('/') else href
            if url in visited:
                continue
            visited.add(url)

            print(f"  [{i+1}/{len(to_visit)}] {href} ({text[:40]})")
            try:
                ok = await bypass_challenge(page, url)
                if ok:
                    await expand_all_nav_items(page)
                    # Collect any new links from this page
                    new_links = await get_all_doc_links(page)
                    for nl in new_links:
                        full = f"{BASE_URL}{nl['href']}" if nl['href'].startswith('/') else nl['href']
                        if full not in visited:
                            to_visit.append((nl['href'], nl['text']))

                    content = await extract_api_content(page)
                    page_key = href.replace('/docs/openapi/', '').replace('/', '-')
                    all_pages[page_key] = content
                    print(f"    -> {len(content['fullText'])} chars, h2: {content['h2'][:3]}")
                else:
                    print(f"    -> FAILED to load")
                await asyncio.sleep(0.5)
            except Exception as e:
                print(f"    -> ERROR: {e}")

        # Save all scraped data
        print(f"\nStep 5: Saving {len(all_pages)} pages...")
        with open(OUT_DIR / 'all_pages_raw.json', 'w', encoding='utf-8') as f:
            json.dump(all_pages, f, ensure_ascii=False, indent=2)

        await browser.close()
        print("\nDone! Check all_pages_raw.json")


if __name__ == '__main__':
    asyncio.run(scrape_all_docs())
