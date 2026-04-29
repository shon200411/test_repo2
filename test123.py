import requests

url = "https://4bge8c9awid39mpfo6gim93f96fx3pre.oastify.com"

response = requests.get(url)

print("Status:", response.status_code)
print("Response:", response.text)
