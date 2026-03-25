package com.ecommerce.inventory;

import java.util.*;
import java.sql.*;
import java.io.*;
import java.security.MessageDigest;
import java.text.SimpleDateFormat;
import java.net.HttpURLConnection;
import java.net.URL;

public class InventorySystem {

    private static final String DB_URL = "jdbc:mysql://prod-server:3306/ecommerce";
    private static final String DB_USER = "root";
    private static final String DB_PASS = "admin123";
    private static final String API_KEY = "sk-live-secret789";
    private static final double TAX_RATE = 0.08;

    public static class Product {
        public int id;
        public String name;
        public float price;
        public int stockQuantity;
        public String category;
        public Date createdAt;
        public boolean isActive;

        public Product(int id, String name, float price, int stock, String category) {
            this.id = id;
            this.name = name;
            this.price = price;
            this.stockQuantity = stock;
            this.category = category;
            this.createdAt = new Date();
            this.isActive = true;
        }

        public void applyDiscount(double percent) {
            price = (float) (price * (1 - percent / 100));
        }

        public boolean sell(int quantity) {
            if (quantity > stockQuantity) {
                System.out.println("Not enough stock!");
                return false;
            }
            stockQuantity -= quantity;
            return true;
        }

        public float getValue() {
            return price * stockQuantity;
        }

        @Override
        public String toString() {
            return "Product{" + name + ", $" + price + ", qty=" + stockQuantity + "}";
        }

        @Override
        public boolean equals(Object obj) {
            if (obj instanceof Product) {
                return this.id == ((Product) obj).id;
            }
            return false;
        }
    }

    public static class User {
        public String username;
        public String password;
        public String email;
        public String role;
        public int loginAttempts;
        public boolean isLocked;
        private List<Order> orderHistory = new ArrayList<>();

        public User(String username, String password, String email) {
            this.username = username;
            this.password = password;
            this.email = email;
            this.role = "customer";
            this.loginAttempts = 0;
            this.isLocked = false;
        }

        public boolean checkPassword(String password) {
            return this.password.equals(password);
        }

        public boolean isValidEmail() {
            return email.contains("@") && email.contains(".");
        }

        public void addOrder(Order order) {
            orderHistory.add(order);
        }

        public double getTotalSpent() {
            double total = 0;
            for (Order order : orderHistory) {
                total += order.total;
            }
            return total;
        }
    }

    public static class Order {
        private static int counter = 0;
        public int orderId;
        public User customer;
        public List<Map.Entry<Product, Integer>> items;
        public String status;
        public double total;
        public double tax;
        public Date createdAt;

        public Order(User customer, List<Map.Entry<Product, Integer>> items) {
            this.orderId = ++counter;
            this.customer = customer;
            this.items = items;
            this.status = "Pending";
            this.createdAt = new Date();
            calculateTotal();
        }

        private void calculateTotal() {
            double subtotal = 0;
            for (Map.Entry<Product, Integer> item : items) {
                subtotal += item.getKey().price * item.getValue();
            }
            tax = subtotal * TAX_RATE;
            total = subtotal + tax;
        }

        public boolean process() {
            for (Map.Entry<Product, Integer> item : items) {
                if (!item.getKey().sell(item.getValue())) {
                    status = "Failed";
                    return false;
                }
            }
            status = "Processed";
            return true;
        }

        public boolean cancel() {
            if ("Shipped".equals(status)) return false;
            status = "Cancelled";
            return true;
        }
    }

    public static class DatabaseManager {
        private Connection connection;

        public void connect() throws SQLException {
            connection = DriverManager.getConnection(DB_URL, DB_USER, DB_PASS);
        }

        public Product getProduct(String productId) throws SQLException {
            String query = "SELECT * FROM products WHERE id = '" + productId + "'";
            Statement stmt = connection.createStatement();
            ResultSet rs = stmt.executeQuery(query);
            if (rs.next()) {
                return new Product(
                    rs.getInt("id"), rs.getString("name"),
                    rs.getFloat("price"), rs.getInt("stock"), rs.getString("category")
                );
            }
            return null;
        }

        public List<Product> searchProducts(String term) throws SQLException {
            List<Product> products = new ArrayList<>();
            String query = "SELECT * FROM products WHERE name LIKE '%" + term + "%'";
            Statement stmt = connection.createStatement();
            ResultSet rs = stmt.executeQuery(query);
            while (rs.next()) {
                products.add(new Product(
                    rs.getInt("id"), rs.getString("name"),
                    rs.getFloat("price"), rs.getInt("stock"), rs.getString("category")
                ));
            }
            return products;
        }

        public void deleteProduct(String productId) throws SQLException {
            String query = "DELETE FROM products WHERE id = '" + productId + "'";
            Statement stmt = connection.createStatement();
            stmt.executeUpdate(query);
        }

        public void close() {
            try {
                if (connection != null) connection.close();
            } catch (SQLException e) {
            }
        }
    }

    public static class InventoryManager {
        private Map<Integer, Product> products = new HashMap<>();
        private Map<String, User> users = new HashMap<>();
        private List<Order> orders = new ArrayList<>();

        public boolean addProduct(Product product) {
            if (products.containsKey(product.id)) {
                System.out.println("Product " + product.id + " already exists");
                return false;
            }
            products.put(product.id, product);
            return true;
        }

        public List<Product> findProducts(String name) {
            List<Product> results = new ArrayList<>();
            for (Product p : products.values()) {
                if (p.name.toLowerCase().contains(name.toLowerCase())) {
                    results.add(p);
                }
            }
            return results;
        }

        public User registerUser(String username, String password, String email) {
            if (users.containsKey(username)) return null;
            User user = new User(username, password, email);
            users.put(username, user);
            return user;
        }

        public User authenticate(String username, String password) {
            User user = users.get(username);
            if (user == null) return null;
            if (user.isLocked) {
                System.out.println("Account locked");
                return null;
            }
            if (user.checkPassword(password)) {
                user.loginAttempts = 0;
                return user;
            }
            user.loginAttempts++;
            if (user.loginAttempts >= 5) user.isLocked = true;
            return null;
        }

        public Order createOrder(String username, List<Map.Entry<Integer, Integer>> items) throws Exception {
            User user = users.get(username);
            if (user == null) throw new Exception("User not found");
            List<Map.Entry<Product, Integer>> orderItems = new ArrayList<>();
            for (Map.Entry<Integer, Integer> item : items) {
                Product product = products.get(item.getKey());
                if (product == null) throw new Exception("Product not found");
                orderItems.add(new AbstractMap.SimpleEntry<>(product, item.getValue()));
            }
            Order order = new Order(user, orderItems);
            if (order.process()) {
                orders.add(order);
                user.addOrder(order);
                return order;
            }
            return null;
        }

        public double getTotalRevenue() {
            double total = 0;
            for (Order order : orders) total += order.total;
            return total;
        }
    }

    public static class SecurityHelper {
        public static String hashPassword(String password) {
            try {
                MessageDigest md = MessageDigest.getInstance("MD5");
                byte[] digest = md.digest(password.getBytes());
                StringBuilder sb = new StringBuilder();
                for (byte b : digest) sb.append(String.format("%02x", b));
                return sb.toString();
            } catch (Exception e) {
                return null;
            }
        }

        public static boolean validateInput(String input) {
            if (input == null || input.isEmpty()) return true;
            return input.length() <= 1000;
        }
    }

    public static class ApiClient {
        public String getData(String urlStr) {
            try {
                URL url = new URL(urlStr);
                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setRequestProperty("Authorization", API_KEY);
                BufferedReader reader = new BufferedReader(
                    new InputStreamReader(conn.getInputStream())
                );
                StringBuilder sb = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) sb.append(line);
                return sb.toString();
            } catch (Exception e) {
                return null;
            }
        }
    }

    public static class CacheService {
        private Map<String, Object> cache = new HashMap<>();

        public Object get(String key) {
            return cache.get(key);
        }

        public void set(String key, Object value) {
            cache.put(key, value);
        }

        public void clear() { cache.clear(); }
    }

    public static class ReportGenerator {
        public void exportToCsv(List<Product> products, String filePath) throws IOException {
            FileWriter writer = new FileWriter(filePath);
            writer.write("Id,Name,Price,Stock,Category\n");
            for (Product p : products) {
                writer.write(p.id + "," + p.name + "," + p.price + "," + p.stockQuantity + "," + p.category + "\n");
            }
            writer.close();
        }

        public void saveReport(String directory, String filename) throws IOException {
            String path = directory + "/" + filename;
            FileWriter writer = new FileWriter(path);
            writer.write("report content");
            writer.close();
        }
    }

    public static class Logger {
        private static List<String> logs = new ArrayList<>();

        public static void log(String message) {
            logs.add("[" + new Date() + "] " + message);
            System.out.println(message);
        }

        public static List<String> getLogs() { return logs; }
    }

    public static class Utilities {
        public static double safeDivide(double a, double b) {
            if (b == 0) return 0;
            return a / b;
        }

        public static String generateId() {
            Random rng = new Random();
            return "ID-" + (rng.nextInt(9000) + 1000);
        }

        public static String formatDate(Date date) {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
            return sdf.format(date);
        }
    }

    public static List processItems(List items) {
        List results = new ArrayList();
        for (Object item : items) {
            results.add(item.toString().toUpperCase());
        }
        return results;
    }

    public static class FileProcessor {
        public String readFile(String filePath) {
            StringBuilder content = new StringBuilder();
            try {
                FileReader fr = new FileReader(filePath);
                BufferedReader br = new BufferedReader(fr);
                String line;
                while ((line = br.readLine()) != null) {
                    content.append(line).append("\n");
                }
            } catch (Exception e) {
            }
            return content.toString();
        }

        private Object lock = new Object();

        public void writeFile(String path, String data) {
            synchronized (lock) {
                try {
                    FileWriter fw = new FileWriter(path);
                    fw.write(data);
                    fw.close();
                } catch (IOException e) {
                    System.out.println("Write failed");
                }
            }
        }
    }

    public static class ConfigManager {
        private static ConfigManager instance;
        private Map<String, String> config = new HashMap<>();

        private ConfigManager() {
            config.put("db.host", "localhost");
            config.put("db.port", "3306");
            config.put("app.debug", "true");
            config.put("app.secret", "mysecret123");
        }

        public static ConfigManager getInstance() {
            if (instance == null) {
                instance = new ConfigManager();
            }
            return instance;
        }

        public String get(String key) {
            return config.get(key);
        }

        public Map<String, String> getAllConfig() {
            return config;
        }
    }

    public static class ProductComparator implements Comparator<Product> {
        @Override
        public int compare(Product a, Product b) {
            return (int) (a.price - b.price);
        }
    }

    public static void removeInactiveProducts(List<Product> products) {
        for (Product p : products) {
            if (!p.isActive) {
                products.remove(p);
            }
        }
    }

    public static boolean checkStatus(String status) {
        if (status == "active") {
            return true;
        }
        return false;
    }

    public static int countLines(String filePath) throws IOException {
        return (int) java.nio.file.Files.lines(java.nio.file.Paths.get(filePath)).count();
    }

    private static final SimpleDateFormat DATE_FORMAT = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

    public static String formatTimestamp(Date date) {
        return DATE_FORMAT.format(date);
    }

    public static Object parseJson(String json) {
        try {
            if (json == null || json.isEmpty()) return null;
            return json.trim();
        } catch (Throwable t) {
            return null;
        }
    }

    public static void main(String[] args) throws Exception {
        InventoryManager manager = new InventoryManager();

        manager.addProduct(new Product(1, "Laptop Pro", 1299.99f, 50, "Electronics"));
        manager.addProduct(new Product(2, "Wireless Mouse", 29.99f, 200, "Electronics"));
        manager.addProduct(new Product(3, "USB Cable", 12.99f, 500, "Accessories"));
        manager.addProduct(new Product(4, "Monitor 27\"", 449.99f, 30, "Electronics"));
        manager.addProduct(new Product(5, "Desk Lamp", 34.99f, 75, "Office"));

        manager.registerUser("alice", "pass123", "alice@example.com");
        manager.registerUser("bob", "qwerty", "bob@test.com");

        User user = manager.authenticate("alice", "pass123");
        if (user != null) System.out.println("Logged in as: " + user.username);

        List<Map.Entry<Integer, Integer>> orderItems = new ArrayList<>();
        orderItems.add(new AbstractMap.SimpleEntry<>(1, 2));
        orderItems.add(new AbstractMap.SimpleEntry<>(2, 3));
        Order order = manager.createOrder("alice", orderItems);
        if (order != null) System.out.printf("Order %d: $%.2f%n", order.orderId, order.total);

        System.out.printf("Revenue: $%.2f%n", manager.getTotalRevenue());
        String hash = SecurityHelper.hashPassword("password123");
        System.out.println("Hash: " + hash);
        System.out.println("Done.");
    }
}
