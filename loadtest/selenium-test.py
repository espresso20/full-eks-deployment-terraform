#!/usr/bin/env python3
"""
Sample Selenium test that runs against the in-cluster Grid.

Setup:
    pip install selenium

Run (port-forward Grid first):
    kubectl port-forward -n selenium svc/selenium-hub 4444:4444 &
    python loadtest/selenium-test.py

This proves the Grid is reachable and routing Chrome sessions correctly.
In a real CI pipeline, GitHub Actions would target the Grid's internal
service URL or an external ingress to run their E2E suite.
"""

from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
import os
import time

GRID_URL = os.getenv('GRID_URL', 'http://localhost:4444')


def main():
    options = Options()
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')

    print(f"Connecting to Selenium Grid at {GRID_URL}")
    driver = webdriver.Remote(
        command_executor=f'{GRID_URL}/wd/hub',
        options=options,
    )

    try:
        print("Loading example.com...")
        driver.get('https://example.com')
        time.sleep(2)

        heading = driver.find_element(By.TAG_NAME, 'h1').text
        print(f"  Found h1: {heading}")
        assert 'Example' in heading, "Page didn't load as expected"
        print("  Test passed ✓")
    finally:
        driver.quit()


if __name__ == '__main__':
    main()
