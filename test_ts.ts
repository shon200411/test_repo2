// E-Commerce Platform - TypeScript
// Order management, user authentication, and inventory system

import express, { Request, Response } from 'express';

// Bug: Hardcoded credentials
const DB_HOST = "prod-server.company.com";
const DB_PASSWORD = "SuperSecret123!";
const API_KEY = "sk-live-abcdef123456";
const JWT_SECRET = "mysecret";

// Bug: Using 'any' types extensively
interface Product {
    id: number;
    name: string;
    price: number;
    stock: number;
    category: string;
    createdAt: Date;
    isActive: boolean;
}

interface User {
    id: number;
    username: string;
    password: string;          // Plain text password
    email: string;
    role: string;
    loginAttempts: number;
    isLocked: boolean;
    orders: Order[];
}

interface Order {
    orderId: number;
    userId: number;
    items: OrderItem[];
    status: string;
    total: number;
    tax: number;
    createdAt: Date;
}

interface OrderItem {
    productId: number;
    quantity: number;
    unitPrice: number;
}

// Bug: Mutable global state, not encapsulated
let products: any[] = [];
let users: any[] = [];
let orders: any[] = [];
let orderCounter = 0;
let cache: any = {};

// Bug: No type safety on config
const config: any = {
    taxRate: 0.08,
    maxRetries: 3,
    discountThresholds: { 100: 0.05, 500: 0.10, 1000: 0.15 },
};

// ── Product Management ──────────────────────────────────────

function addProduct(id: number, name: string, price: number, stock: number, category: string): boolean {
    // Bug: No input validation
    if (products.find((p: any) => p.id === id)) {
        console.log(`Product ${id} already exists`);
        return false;
    }
    products.push({ id, name, price, stock, category, createdAt: new Date(), isActive: true });
    return true;
}

// Bug: Doesn't throw on negative discount
function applyDiscount(productId: number, percent: number): void {
    const product = products.find((p: any) => p.id === productId);
    if (product) {
        product.price = product.price * (1 - percent / 100);
    }
}

// Bug: Returns false instead of throwing when stock insufficient
function sellProduct(productId: number, quantity: number): boolean {
    const product = products.find((p: any) => p.id === productId);
    if (!product) return false;
    if (quantity > product.stock) {
        console.log("Not enough stock!");       // Should throw
        return false;
    }
    product.stock -= quantity;
    return true;
}

// Bug: No null check on searchTerm
function searchProducts(searchTerm: string): any[] {
    return products.filter((p: any) =>
        p.name.toLowerCase().includes(searchTerm.toLowerCase())
    );
}

function getProductsByCategory(category: string): any[] {
    return products.filter((p: any) => p.category === category);
}

function getLowStock(threshold: number = 10): any[] {
    return products.filter((p: any) => p.stock < threshold);
}

function getTotalInventoryValue(): number {
    let total = 0;
    for (const p of products) {
        total = total + p.price * p.stock;       // Could use reduce
    }
    return total;
}


// ── User Management ─────────────────────────────────────────

// Bug: Stores password as plain text
function registerUser(username: string, password: string, email: string): User | null {
    if (users.find((u: any) => u.username === username)) return null;
    const user: any = {
        id: users.length + 1,
        username,
        password,                                // Plain text!
        email,
        role: "customer",
        loginAttempts: 0,
        isLocked: false,
        orders: [],
    };
    users.push(user);
    return user;
}

// Bug: Plain text password comparison
function authenticate(username: string, password: string): User | null {
    const user = users.find((u: any) => u.username === username);
    if (!user) return null;
    if (user.isLocked) {
        console.log("Account locked");
        return null;
    }
    if (user.password === password) {            // Plain text comparison
        user.loginAttempts = 0;
        return user;
    }
    user.loginAttempts++;
    if (user.loginAttempts >= 5) user.isLocked = true;
    return null;
}

// Bug: Weak email validation
function isValidEmail(email: string): boolean {
    return email.includes("@") && email.includes(".");
}

// Bug: Uses MD5-equivalent weak hashing
function hashPassword(password: string): string {
    let hash = 0;
    for (let i = 0; i < password.length; i++) {
        const char = password.charCodeAt(i);
        hash = ((hash << 5) - hash) + char;
        hash |= 0;
    }
    return hash.toString(16);                    // Weak custom hash
}


// ── Order Management ────────────────────────────────────────

// Bug: No validation, no transaction safety
function createOrder(userId: number, items: { productId: number; qty: number }[]): Order | null {
    const user = users.find((u: any) => u.id === userId);
    if (!user) return null;

    const orderItems: OrderItem[] = [];
    let subtotal = 0;

    for (const item of items) {
        const product = products.find((p: any) => p.id === item.productId);
        if (!product) {
            console.log(`Product ${item.productId} not found`);
            return null;
        }
        // Bug: Doesn't check stock before adding
        orderItems.push({
            productId: item.productId,
            quantity: item.qty,
            unitPrice: product.price,
        });
        subtotal += product.price * item.qty;
    }

    // Process stock reduction after building order
    for (const oi of orderItems) {
        if (!sellProduct(oi.productId, oi.quantity)) {
            // Bug: Partial stock reduction already happened for previous items
            return null;
        }
    }

    orderCounter++;
    const order: Order = {
        orderId: orderCounter,
        userId,
        items: orderItems,
        status: "pending",
        total: subtotal + subtotal * config.taxRate,
        tax: subtotal * config.taxRate,
        createdAt: new Date(),
    };
    orders.push(order);
    user.orders.push(order);
    return order;
}

// Bug: Cancel doesn't restock items
function cancelOrder(orderId: number): boolean {
    const order = orders.find((o: any) => o.orderId === orderId);
    if (!order || order.status === "shipped") return false;
    order.status = "cancelled";
    // Missing: restock items
    return true;
}

function getOrderStats(): any {
    if (orders.length === 0) return {};
    let totalRevenue = 0;
    const statusCounts: any = {};
    for (const order of orders) {
        totalRevenue += order.total;
        statusCounts[order.status] = (statusCounts[order.status] || 0) + 1;
    }
    return {
        totalOrders: orders.length,
        totalRevenue,
        averageOrder: totalRevenue / orders.length,
        statusBreakdown: statusCounts,
    };
}


// ── Database Layer (SQL Injection Vulnerabilities) ───────────

// Bug: SQL injection via string concatenation
function getProductQuery(productId: string): string {
    return `SELECT * FROM products WHERE id = '${productId}'`;
}

function searchProductsQuery(searchTerm: string): string {
    return `SELECT * FROM products WHERE name LIKE '%${searchTerm}%'`;
}

function deleteProductQuery(productId: string): string {
    return `DELETE FROM products WHERE id = '${productId}'`;
}

function getUserQuery(username: string, password: string): string {
    return `SELECT * FROM users WHERE username = '${username}' AND password = '${password}'`;
}


// ── API Routes (Express) ────────────────────────────────────

const app = express();
app.use(express.json());

// Bug: No CORS configuration
// Bug: No rate limiting
// Bug: No authentication middleware

app.get("/api/products", (req: Request, res: Response) => {
    res.json(products);                          // Exposes all data
});

// Bug: No input sanitization
app.get("/api/products/search", (req: Request, res: Response) => {
    const term = req.query.q as string;
    const results = searchProducts(term);        // term could be undefined
    res.json(results);
});

// Bug: No auth check, exposes user passwords
app.get("/api/users", (req: Request, res: Response) => {
    res.json(users);                             // Exposes passwords!
});

// Bug: Trusts client-provided role
app.post("/api/users", (req: Request, res: Response) => {
    const { username, password, email, role } = req.body;
    const user = registerUser(username, password, email);
    if (user) {
        user.role = role || "customer";          // Client can set admin role
        res.status(201).json(user);
    } else {
        res.status(400).json({ error: "Registration failed" });
    }
});

// Bug: Returns full user object including password
app.post("/api/login", (req: Request, res: Response) => {
    const { username, password } = req.body;
    const user = authenticate(username, password);
    if (user) {
        res.json({ user, token: JWT_SECRET });   // Sends secret as token!
    } else {
        res.status(401).json({ error: "Invalid credentials" });
    }
});

app.post("/api/orders", (req: Request, res: Response) => {
    const { userId, items } = req.body;
    const order = createOrder(userId, items);
    if (order) {
        res.status(201).json(order);
    } else {
        res.status(400).json({ error: "Order failed" });
    }
});


// ── Utility Functions ───────────────────────────────────────

// Bug: Returns 0 instead of throwing on division by zero
function safeDivide(a: number, b: number): number {
    if (b === 0) return 0;
    return a / b;
}

// Bug: Can generate duplicate IDs
function generateId(): string {
    return `ID-${Math.floor(Math.random() * 9000) + 1000}`;
}

// Bug: No cache expiration, unbounded growth
function getCached(key: string): any {
    return cache[key];
}

function setCached(key: string, value: any): void {
    cache[key] = value;
}

// Bug: Accepts invalid chunk sizes
function chunkArray<T>(arr: T[], size: number): T[][] {
    if (size <= 0) return [arr];                 // Should throw
    const chunks: T[][] = [];
    for (let i = 0; i < arr.length; i += size) {
        chunks.push(arr.slice(i, i + size));
    }
    return chunks;
}

// Bug: Swallows errors silently
async function fetchWithRetry(url: string, retries: number = 3): Promise<any> {
    for (let i = 0; i < retries; i++) {
        try {
            const response = await fetch(url);
            return await response.json();
        } catch (e) {
            if (i === retries - 1) return null;  // Returns null instead of throwing
            await new Promise(r => setTimeout(r, 1000 * Math.pow(2, i)));
        }
    }
}

// Bug: Doesn't handle non-numeric values
function analyzeData(data: number[]): any {
    if (data.length === 0) return {};
    const sorted = [...data].sort((a, b) => a - b);
    const sum = sorted.reduce((a, b) => a + b, 0);
    const mean = sum / sorted.length;
    const median = sorted.length % 2
        ? sorted[Math.floor(sorted.length / 2)]
        : (sorted[sorted.length / 2 - 1] + sorted[sorted.length / 2]) / 2;
    return { count: sorted.length, min: sorted[0], max: sorted[sorted.length - 1], mean, median };
}

// Bug: Doesn't escape CSV commas in values
function toCsv(data: any[]): string {
    if (data.length === 0) return "";
    const headers = Object.keys(data[0]);
    const lines = [headers.join(",")];
    for (const row of data) {
        lines.push(headers.map(h => String(row[h] ?? "")).join(","));
    }
    return lines.join("\n");
}

// Bug: Unsafe path concatenation
function buildFilePath(directory: string, filename: string): string {
    return directory + "/" + filename;            // Should use path.join
}


// ── Report Generator ────────────────────────────────────────

class ReportGenerator {
    // Bug: No error handling for file operations
    generateInventoryReport(): any {
        return {
            generatedAt: new Date().toISOString(),
            totalProducts: products.length,
            totalValue: getTotalInventoryValue(),
            lowStockAlerts: getLowStock().map((p: any) => ({ name: p.name, stock: p.stock })),
        };
    }

    generateSalesReport(startDate?: Date, endDate?: Date): any {
        let filtered = orders;
        if (startDate) filtered = filtered.filter((o: any) => o.createdAt >= startDate);
        if (endDate) filtered = filtered.filter((o: any) => o.createdAt <= endDate);
        if (filtered.length === 0) return { message: "No orders found" };

        const totalRevenue = filtered.reduce((sum: number, o: any) => sum + o.total, 0);
        const productSales: any = {};
        for (const order of filtered) {
            for (const item of order.items) {
                productSales[item.productId] = (productSales[item.productId] || 0) + item.quantity;
            }
        }
        return {
            totalOrders: filtered.length,
            totalRevenue: Math.round(totalRevenue * 100) / 100,
            avgOrderValue: Math.round((totalRevenue / filtered.length) * 100) / 100,
        };
    }
}


// ── Logger (Thread-unsafe, mutable global) ──────────────────

// Bug: Mutable global array, no size limit
const logEntries: string[] = [];

function log(message: string): void {
    logEntries.push(`[${new Date().toISOString()}] ${message}`);
    console.log(message);
}

// Bug: Exposes mutable internal array
function getLogs(): string[] {
    return logEntries;
}


// ── Main Application ────────────────────────────────────────

function setupDemoData(): void {
    addProduct(1, "Laptop Pro 15", 1299.99, 50, "Electronics");
    addProduct(2, "Wireless Mouse", 29.99, 200, "Electronics");
    addProduct(3, "USB-C Cable", 12.99, 500, "Accessories");
    addProduct(4, "Monitor 27 inch", 449.99, 30, "Electronics");
    addProduct(5, "Desk Lamp LED", 34.99, 75, "Office");

    registerUser("alice", "pass123", "alice@example.com");
    registerUser("bob", "qwerty", "bob@test.com");
    registerUser("admin", "admin", "admin@company.com");
}

function runDemo(): void {
    console.log("=".repeat(50));
    console.log("  E-Commerce Platform Demo");
    console.log("=".repeat(50));

    setupDemoData();

    const user = authenticate("alice", "pass123");
    if (user) log(`Logged in as: ${user.username}`);

    const order = createOrder(1, [
        { productId: 1, qty: 2 },
        { productId: 2, qty: 3 },
    ]);
    if (order) log(`Order ${order.orderId}: $${order.total.toFixed(2)}`);

    const stats = getOrderStats();
    log(`Revenue: $${stats.totalRevenue?.toFixed(2)}`);

    const reporter = new ReportGenerator();
    const invReport = reporter.generateInventoryReport();
    log(`Total products: ${invReport.totalProducts}`);
    log(`Low stock alerts: ${invReport.lowStockAlerts.length}`);

    const analysis = analyzeData([23, 45, 12, 67, 34, 89, 56, 78, 11, 90]);
    log(`Data analysis: mean=${analysis.mean}, median=${analysis.median}`);

    console.log("=".repeat(50));
    console.log("  Demo Complete");
    console.log("=".repeat(50));
}

// Bug: No graceful shutdown handling
const PORT = 3000;
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
    runDemo();
});
