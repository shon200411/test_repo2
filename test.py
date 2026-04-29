import requests

url = "https://ovnyswtug2xnt69z8q026tnztqzhn8bx.oastify.com/endpoint"

response = requests.get(url)

print("Status:", response.status_code)
print("Response:", response.text)
