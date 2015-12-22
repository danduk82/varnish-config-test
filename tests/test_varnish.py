import json
import sys
import unittest
import requests


class VarnishTestCase(unittest.TestCase):

    def setUp(self):
        self.url = "http://localhost"

    def tearDown(self):
        self.url = None

    def test_empty_payload(self):
        resp = requests.get(self.url + '/')

        self.assertTrue(resp.status_code == 200)


if __name__ == '__main__':
    unittest.main()
