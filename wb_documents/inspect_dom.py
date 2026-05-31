"""Inspect WB docs page DOM structure to find all section links."""
import asyncio
import json
from pathlib import Path
from playwright.async_api import async_playwright
from playwright_stealth import Stealth

OUT_DIR = Path(__file__).parent
stealth = Stealth()


async def main():
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True, args=['--no-sandbox', '--disable-blink-features=AutomationControlled'])
        context = await browser.new_context(
            user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            viewport={'width': 1920, 'height': 1080},
            locale='ru-RU',
        )
        page = await context.new_page()
        await stealth.apply_stealth_async(page)

        await page.goto("https://dev.wildberries.ru/docs/openapi/api-information", wait_until="domcontentloaded", timeout=60000)
        # Wait for challenge
        await page.wait_for_function("() => !document.title.includes('Почти готово')", timeout=30000)
        await asyncio.sleep(3)

        # Get full page HTML structure
        result = await page.evaluate("""
            () => {
                // Find all elements with 'sidebar' or 'aside' or 'left' in class
                const candidates = [];
                document.querySelectorAll('*').forEach(el => {
                    const cls = el.className;
                    if (typeof cls === 'string' && (
                        cls.includes('sidebar') || cls.includes('Sidebar') ||
                        cls.includes('aside') || cls.includes('left') ||
                        cls.includes('Left') || cls.includes('tree') ||
                        cls.includes('Tree') || cls.includes('catalog') ||
                        cls.includes('chapter') || cls.includes('toc')
                    )) {
                        candidates.push({
                            tag: el.tagName,
                            cls: cls.substring(0, 100),
                            children: el.children.length,
                            text: el.innerText.substring(0, 200),
                            html: el.outerHTML.substring(0, 500),
                        });
                    }
                });

                // Get all a[href] with text
                const allLinks = [];
                document.querySelectorAll('a[href]').forEach(a => {
                    const href = a.href;
                    const text = a.innerText.trim();
                    if (text && href.includes('wildberries')) {
                        allLinks.push({ href, text: text.substring(0, 80) });
                    }
                });

                // Get full body HTML (first 20k)
                const bodyHTML = document.body.innerHTML.substring(0, 20000);

                // List all divs/sections with significant content and links
                const contentBlocks = [];
                document.querySelectorAll('div, section, aside').forEach(el => {
                    const links = el.querySelectorAll('a[href*="/docs"]');
                    if (links.length > 3) {
                        contentBlocks.push({
                            tag: el.tagName,
                            cls: (el.className || '').substring(0, 100),
                            linkCount: links.length,
                            links: Array.from(links).map(a => ({ href: a.getAttribute('href'), text: a.innerText.trim().substring(0, 50) })).slice(0, 30),
                            html: el.outerHTML.substring(0, 1000),
                        });
                    }
                });

                return { candidates: candidates.slice(0, 20), allLinks, bodyHTML, contentBlocks };
            }
        """)

        with open(OUT_DIR / 'dom_debug.json', 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)

        print(f"Found {len(result['candidates'])} sidebar-like elements")
        print(f"Found {len(result['allLinks'])} links with text")
        print(f"Found {len(result['contentBlocks'])} content blocks with doc links")
        print("\nContent blocks with doc links:")
        for b in result['contentBlocks']:
            print(f"  {b['tag']}.{b['cls'][:50]}: {b['linkCount']} links")
            for l in b['links'][:5]:
                print(f"    {l['href']} -> {l['text']}")
        print("\nAll links:")
        for l in result['allLinks']:
            print(f"  {l['href']} -> {l['text']}")

        await page.screenshot(path=str(OUT_DIR / 'screenshot_full.png'), full_page=True)
        await browser.close()


asyncio.run(main())
