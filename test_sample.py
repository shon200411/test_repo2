"""
Inventory Management System
============================
A sample application for managing products, orders, and users.
"""

import os
import sys
import json
import hashlib
import sqlite3
import random
import time
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Tuple


# ── Constants ──────────────────────────────────────────────────────────
DB_PASSWORD = "admin123"          # Hardcoded credential
API_KEY = "sk-abc123secretkey"    # Hardcoded API key
MAX_RETRIES = 3
DEFAULT_CURRENCY = "USD"
TAX_RATE = 0.08
DISCOUNT_THRESHOLDS = {100: 0.05, 500: 0.10, 1000: 0.15}


# ── Models ─────────────────────────────────────────────────────────────
class Product:
    def __init__(self, id, name, price, quantity, category):
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
        self.category = category
        self.created_at = datetime.now()
        self.updated_at = None

    def __str__(self):
        return f"Product({self.name}, ${self.price}, qty={self.quantity})"

    def __repr__(self):
        return self.__str__()

    def apply_discount(self, percentage):
        if percentage < 0 or percentage > 100:
            raise ValueError("Discount must be between 0 and 100")
        self.price = self.price * (1 - percentage / 100)
        self.updated_at = datetime.now()
        return self.price

    def restock(self, amount):
        self.quantity += amount
        self.updated_at = datetime.now()

    def sell(self, amount):
        if amount > self.quantity:
            print("Not enough stock!")    # Should raise exception instead of print
            return False
        self.quantity = self.quantity - amount
        self.updated_at = datetime.now()
        return True

    def get_value(self):
        return self.price * self.quantity

    def to_dict(self):
        return {
            "id": self.id, "name": self.name, "price": self.price,
            "quantity": self.quantity, "category": self.category,
            "created_at": str(self.created_at),
            "updated_at": str(self.updated_at) if self.updated_at else None
        }


class User:
    def __init__(self, username, password, email, role="customer"):
        self.username = username
        self.password = password          # Storing plain text password
        self.email = email
        self.role = role
        self.created_at = datetime.now()
        self.login_attempts = 0
        self.is_locked = False
        self.order_history = []

    def check_password(self, password):
        return self.password == password   # Plain text comparison

    def change_password(self, old_password, new_password):
        if self.check_password(old_password):
            self.password = new_password   # Still plain text
            return True
        return False

    def lock_account(self):
        self.is_locked = True

    def unlock_account(self):
        self.is_locked = False
        self.login_attempts = 0

    def add_order(self, order):
        self.order_history.append(order)

    def get_total_spent(self):
        total = 0
        for order in self.order_history:
            total += order.total
        return total


class Order:
    _counter = 0

    def __init__(self, user, items):
        Order._counter += 1
        self.order_id = Order._counter
        self.user = user
        self.items = items
        self.status = "pending"
        self.created_at = datetime.now()
        self.shipped_at = None
        self.total = 0
        self.tax = 0
        self.discount = 0
        self._calculate_total()

    def _calculate_total(self):
        subtotal = 0
        for product, qty in self.items:
            subtotal += product.price * qty
        # Apply bulk discount
        self.discount = 0
        for threshold, rate in DISCOUNT_THRESHOLDS.items():
            if subtotal >= threshold:
                self.discount = rate
        # Bug: discount is set to rate, not the discount amount
        self.tax = subtotal * TAX_RATE
        self.total = subtotal + self.tax - (subtotal * self.discount)

    def process(self):
        for product, qty in self.items:
            if not product.sell(qty):
                self.status = "failed"
                return False
        self.status = "processed"
        return True

    def ship(self):
        if self.status != "processed":
            return False
        self.status = "shipped"
        self.shipped_at = datetime.now()
        return True

    def cancel(self):
        if self.status == "shipped":
            return False
        # Bug: doesn't restock items when cancelling
        self.status = "cancelled"
        return True

    def to_dict(self):
        return {
            "order_id": self.order_id, "user": self.user.username,
            "items": [(p.name, q) for p, q in self.items],
            "status": self.status, "total": self.total,
            "created_at": str(self.created_at),
        }


# ── Inventory Manager ─────────────────────────────────────────────────
class InventoryManager:
    def __init__(self):
        self.products = {}
        self.users = {}
        self.orders = []
        self.log = []

    def add_product(self, product):
        if product.id in self.products:
            print(f"Product {product.id} already exists")
            return False
        self.products[product.id] = product
        self._log(f"Added product: {product.name}")
        return True

    def remove_product(self, product_id):
        if product_id in self.products:
            del self.products[product_id]
            return True
        return False

    def find_product(self, name):
        results = []
        for pid, product in self.products.items():
            if name.lower() in product.name.lower():
                results.append(product)
        return results

    def get_products_by_category(self, category):
        return [p for p in self.products.values() if p.category == category]

    def get_low_stock(self, threshold=10):
        return [p for p in self.products.values() if p.quantity < threshold]

    def get_total_inventory_value(self):
        total = 0
        for product in self.products.values():
            total = total + product.get_value()
        return total

    def register_user(self, username, password, email, role="customer"):
        if username in self.users:
            return None
        user = User(username, password, email, role)
        self.users[username] = user
        return user

    def authenticate(self, username, password):
        user = self.users.get(username)
        if not user:
            return None
        if user.is_locked:
            print("Account is locked")
            return None
        if user.check_password(password):
            user.login_attempts = 0
            return user
        else:
            user.login_attempts += 1
            if user.login_attempts >= 5:
                user.lock_account()
            return None

    def create_order(self, username, items):
        user = self.users.get(username)
        if not user:
            raise ValueError(f"User '{username}' not found")
        order_items = []
        for product_id, qty in items:
            product = self.products.get(product_id)
            if not product:
                raise ValueError(f"Product '{product_id}' not found")
            if qty <= 0:
                raise ValueError("Quantity must be positive")
            order_items.append((product, qty))
        order = Order(user, order_items)
        if order.process():
            self.orders.append(order)
            user.add_order(order)
            self._log(f"Order {order.order_id} created for {username}")
            return order
        return None

    def get_order_stats(self):
        if not self.orders:
            return {}
        total_revenue = 0
        status_counts = {}
        for order in self.orders:
            total_revenue += order.total
            status_counts[order.status] = status_counts.get(order.status, 0) + 1
        return {
            "total_orders": len(self.orders),
            "total_revenue": total_revenue,
            "average_order": total_revenue / len(self.orders),
            "status_breakdown": status_counts,
        }

    def _log(self, message):
        entry = f"[{datetime.now()}] {message}"
        self.log.append(entry)
        print(entry)


# ── Database Operations ───────────────────────────────────────────────
class DatabaseManager:
    def __init__(self, db_path="inventory.db"):
        self.db_path = db_path
        self.connection = None

    def connect(self):
        self.connection = sqlite3.connect(self.db_path)
        self._create_tables()

    def _create_tables(self):
        cursor = self.connection.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS products (
                id TEXT PRIMARY KEY, name TEXT NOT NULL,
                price REAL NOT NULL, quantity INTEGER NOT NULL, category TEXT
            )
        """)
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                username TEXT PRIMARY KEY, password TEXT NOT NULL,
                email TEXT, role TEXT DEFAULT 'customer'
            )
        """)
        self.connection.commit()

    def save_product(self, product):
        cursor = self.connection.cursor()
        # SQL injection vulnerability - using string formatting
        query = f"INSERT OR REPLACE INTO products VALUES ('{product.id}', '{product.name}', {product.price}, {product.quantity}, '{product.category}')"
        cursor.execute(query)
        self.connection.commit()

    def get_product(self, product_id):
        cursor = self.connection.cursor()
        # SQL injection vulnerability
        query = f"SELECT * FROM products WHERE id = '{product_id}'"
        cursor.execute(query)
        row = cursor.fetchone()
        if row:
            return Product(row[0], row[1], row[2], row[3], row[4])
        return None

    def search_products(self, search_term):
        cursor = self.connection.cursor()
        # SQL injection vulnerability
        query = f"SELECT * FROM products WHERE name LIKE '%{search_term}%'"
        cursor.execute(query)
        return [Product(*row) for row in cursor.fetchall()]

    def save_user(self, user):
        cursor = self.connection.cursor()
        cursor.execute(
            "INSERT OR REPLACE INTO users VALUES (?, ?, ?, ?)",
            (user.username, user.password, user.email, user.role)
        )
        self.connection.commit()

    def delete_product(self, product_id):
        cursor = self.connection.cursor()
        cursor.execute(f"DELETE FROM products WHERE id = '{product_id}'")  # SQL injection
        self.connection.commit()

    def close(self):
        if self.connection:
            self.connection.close()


# ── Report Generator ──────────────────────────────────────────────────
class ReportGenerator:
    def __init__(self, inventory_manager):
        self.manager = inventory_manager

    def generate_inventory_report(self):
        report = {
            "generated_at": str(datetime.now()),
            "total_products": len(self.manager.products),
            "total_value": self.manager.get_total_inventory_value(),
            "categories": {},
            "low_stock_alerts": [],
        }
        for product in self.manager.products.values():
            cat = product.category
            if cat not in report["categories"]:
                report["categories"][cat] = {"count": 0, "value": 0}
            report["categories"][cat]["count"] += 1
            report["categories"][cat]["value"] += product.get_value()
        for product in self.manager.get_low_stock():
            report["low_stock_alerts"].append({
                "product": product.name, "current_stock": product.quantity,
            })
        return report

    def generate_sales_report(self, start_date=None, end_date=None):
        filtered_orders = []
        for order in self.manager.orders:
            if start_date and order.created_at < start_date:
                continue
            if end_date and order.created_at > end_date:
                continue
            filtered_orders.append(order)
        if not filtered_orders:
            return {"message": "No orders found in the specified period"}
        total_revenue = sum(o.total for o in filtered_orders)
        product_sales = {}
        for order in filtered_orders:
            for product, qty in order.items:
                if product.name not in product_sales:
                    product_sales[product.name] = 0
                product_sales[product.name] += qty
        top_products = sorted(product_sales.items(), key=lambda x: x[1], reverse=True)[:5]
        return {
            "total_orders": len(filtered_orders),
            "total_revenue": round(total_revenue, 2),
            "average_order_value": round(total_revenue / len(filtered_orders), 2),
            "top_products": top_products,
        }

    def export_to_json(self, report, filename):
        # Missing error handling for file operations
        with open(filename, "w") as f:
            json.dump(report, f, indent=2)

    def export_to_csv(self, data, filename):
        with open(filename, "w") as f:
            if not data:
                return
            headers = data[0].keys()
            f.write(",".join(headers) + "\n")
            for row in data:
                # Bug: doesn't handle commas in values
                values = [str(row.get(h, "")) for h in headers]
                f.write(",".join(values) + "\n")


# ── Utility Functions ─────────────────────────────────────────────────
def format_currency(amount, currency=DEFAULT_CURRENCY):
    if currency == "USD":
        return f"${amount:.2f}"
    elif currency == "EUR":
        return f"€{amount:.2f}"
    elif currency == "GBP":
        return f"£{amount:.2f}"
    else:
        return f"{amount:.2f} {currency}"


def calculate_shipping_cost(weight, distance, express=False):
    base_rate = 5.0
    cost = base_rate + (weight * 0.5) + (distance * 0.01)
    if express:
        cost *= 2.0
    # Bug: negative weight or distance not validated
    return round(cost, 2)


def validate_email(email):
    if "@" in email and "." in email:
        return True
    return False        # Doesn't check format properly


def generate_product_id():
    return f"PRD-{random.randint(1000, 9999)}"   # Can generate duplicates


def hash_password(password):
    return hashlib.md5(password.encode()).hexdigest()    # MD5 is weak


def parse_date(date_string):
    formats = ["%Y-%m-%d", "%d/%m/%Y", "%m-%d-%Y"]
    for fmt in formats:
        try:
            return datetime.strptime(date_string, fmt)
        except ValueError:
            continue
    return None    # Silently returns None instead of raising


def retry_operation(func, max_retries=MAX_RETRIES, delay=1):
    for attempt in range(max_retries):
        try:
            return func()
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            time.sleep(delay * (2 ** attempt))
            print(f"Retry {attempt + 1}/{max_retries}: {e}")


def flatten_dict(d, parent_key="", sep="_"):
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)


def chunk_list(lst, chunk_size):
    if chunk_size <= 0:
        return [lst]         # Bug: should raise error for invalid chunk size
    return [lst[i:i + chunk_size] for i in range(0, len(lst), chunk_size)]


def merge_dicts(*dicts):
    result = {}
    for d in dicts:
        result.update(d)     # Later values overwrite earlier ones silently
    return result


def safe_divide(a, b):
    if b == 0:
        return 0             # Returns 0 instead of raising or returning None
    return a / b


# ── Data Processing ───────────────────────────────────────────────────
class DataProcessor:
    def __init__(self):
        self.cache = {}
        self.processing_count = 0

    def process_batch(self, items):
        results = []
        for item in items:
            try:
                processed = self._process_item(item)
                results.append(processed)
                self.processing_count += 1
            except Exception as e:
                print(f"Error processing item: {e}")    # Swallows exception
                continue
        return results

    def _process_item(self, item):
        if isinstance(item, dict):
            return {k: str(v).upper() for k, v in item.items()}
        elif isinstance(item, list):
            return [str(i).upper() for i in item]
        elif isinstance(item, str):
            return item.upper()
        else:
            return str(item)

    def get_cached(self, key):
        return self.cache.get(key)     # No cache expiration

    def set_cached(self, key, value):
        self.cache[key] = value        # No size limit

    def clear_cache(self):
        self.cache = {}

    def analyze_data(self, data_list):
        if not data_list:
            return {}
        # Bug: doesn't handle non-numeric values
        sorted_data = sorted(data_list)
        n = len(sorted_data)
        mean = sum(sorted_data) / n
        median = sorted_data[n // 2] if n % 2 else (sorted_data[n // 2 - 1] + sorted_data[n // 2]) / 2
        variance = sum((x - mean) ** 2 for x in sorted_data) / n
        return {
            "count": n, "min": sorted_data[0], "max": sorted_data[-1],
            "mean": round(mean, 2), "median": median,
            "std_dev": round(variance ** 0.5, 2),
        }


# ── Main Application ──────────────────────────────────────────────────
def setup_demo_data(manager):
    products = [
        Product("P001", "Laptop Pro 15", 1299.99, 50, "Electronics"),
        Product("P002", "Wireless Mouse", 29.99, 200, "Electronics"),
        Product("P003", "USB-C Cable", 12.99, 500, "Accessories"),
        Product("P004", "Monitor 27 inch", 449.99, 30, "Electronics"),
        Product("P005", "Keyboard Mechanical", 89.99, 150, "Electronics"),
        Product("P006", "Desk Lamp LED", 34.99, 75, "Office"),
        Product("P007", "Notebook A5", 4.99, 1000, "Stationery"),
        Product("P008", "Pen Set Premium", 19.99, 300, "Stationery"),
        Product("P009", "Webcam HD", 59.99, 8, "Electronics"),
        Product("P010", "Phone Stand", 15.99, 3, "Accessories"),
    ]
    for p in products:
        manager.add_product(p)
    manager.register_user("alice", "pass123", "alice@example.com", "admin")
    manager.register_user("bob", "qwerty", "bob@example.com")
    manager.register_user("charlie", "abc", "charlie@example.com")
    return manager


def run_demo():
    print("=" * 60)
    print("  Inventory Management System - Demo")
    print("=" * 60)

    manager = InventoryManager()
    setup_demo_data(manager)

    user = manager.authenticate("alice", "pass123")
    if user:
        print(f"\nLogged in as: {user.username} ({user.role})")

    order1 = manager.create_order("alice", [("P001", 2), ("P002", 3)])
    order2 = manager.create_order("bob", [("P003", 10), ("P007", 20)])
    if order1:
        print(f"\nOrder 1: {format_currency(order1.total)}")
    if order2:
        print(f"Order 2: {format_currency(order2.total)}")

    reporter = ReportGenerator(manager)
    inv_report = reporter.generate_inventory_report()
    sales_report = reporter.generate_sales_report()

    print(f"\n--- Inventory Report ---")
    print(f"Total products: {inv_report['total_products']}")
    print(f"Total value: {format_currency(inv_report['total_value'])}")
    print(f"Low stock items: {len(inv_report['low_stock_alerts'])}")
    print(f"\n--- Sales Report ---")
    print(f"Total orders: {sales_report.get('total_orders', 0)}")
    print(f"Revenue: {format_currency(sales_report.get('total_revenue', 0))}")

    stats = manager.get_order_stats()
    print(f"\n--- Order Stats ---")
    for key, value in stats.items():
        print(f"  {key}: {value}")

    processor = DataProcessor()
    analysis = processor.analyze_data([23, 45, 12, 67, 34, 89, 56, 78, 11, 90])
    print(f"\n--- Data Analysis ---")
    for key, value in analysis.items():
        print(f"  {key}: {value}")

    print("\n" + "=" * 60)
    print("  Demo Complete")
    print("=" * 60)


if __name__ == "__main__":
    run_demo()
