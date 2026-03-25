using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace ECommerce.Services
{
    // Bug: Hardcoded credentials
    public static class AppConfig
    {
        public const string DbConnectionString = "Server=prod-db;Database=ECommerceDB;User=sa;Password=Admin123!";
        public const string ApiKey = "sk-live-abc123secretkey";
        public const string EncryptionKey = "MySecretKey12345";
        public static readonly int MaxRetries = 3;
        public static readonly double TaxRate = 0.08;
    }

    // Bug: No input validation, mutable properties without protection
    public class Product
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public double Price { get; set; }           // Should be decimal for money
        public int StockQuantity { get; set; }
        public string Category { get; set; }
        public DateTime CreatedAt { get; set; }
        public bool IsActive { get; set; }

        public Product() { }

        public Product(int id, string name, double price, int stock, string category)
        {
            Id = id;
            Name = name;
            Price = price;
            StockQuantity = stock;
            Category = category;
            CreatedAt = DateTime.Now;
            IsActive = true;
        }

        // Bug: Doesn't validate negative discount
        public void ApplyDiscount(double percent)
        {
            Price = Price * (1 - percent / 100);
        }

        // Bug: Returns false instead of throwing when out of stock
        public bool Sell(int quantity)
        {
            if (quantity > StockQuantity)
            {
                Console.WriteLine("Not enough stock!");
                return false;
            }
            StockQuantity -= quantity;
            return true;
        }

        public double GetValue() => Price * StockQuantity;
    }

    // Bug: Stores password as plain text
    public class User
    {
        public int Id { get; set; }
        public string Username { get; set; }
        public string Password { get; set; }        // Plain text!
        public string Email { get; set; }
        public string Role { get; set; }
        public int LoginAttempts { get; set; }
        public bool IsLocked { get; set; }
        public List<Order> OrderHistory { get; set; } = new List<Order>();

        // Bug: Plain text password comparison
        public bool CheckPassword(string password)
        {
            return Password == password;
        }

        // Bug: Weak email validation
        public bool IsValidEmail()
        {
            return Email.Contains("@") && Email.Contains(".");
        }

        public decimal GetTotalSpent()
        {
            decimal total = 0;
            foreach (var order in OrderHistory)
                total += (decimal)order.Total;       // Lossy cast from double
            return total;
        }
    }

    public class Order
    {
        private static int _counter = 0;
        public int OrderId { get; set; }
        public User Customer { get; set; }
        public List<(Product Product, int Quantity)> Items { get; set; }
        public string Status { get; set; }
        public double Total { get; set; }            // Should be decimal
        public double Tax { get; set; }
        public DateTime CreatedAt { get; set; }

        public Order(User customer, List<(Product, int)> items)
        {
            OrderId = ++_counter;                    // Not thread-safe
            Customer = customer;
            Items = items;
            Status = "Pending";
            CreatedAt = DateTime.Now;
            CalculateTotal();
        }

        private void CalculateTotal()
        {
            double subtotal = 0;
            foreach (var (product, qty) in Items)
                subtotal += product.Price * qty;
            Tax = subtotal * AppConfig.TaxRate;
            Total = subtotal + Tax;
        }

        public bool Process()
        {
            foreach (var (product, qty) in Items)
            {
                if (!product.Sell(qty))
                {
                    Status = "Failed";
                    return false;
                }
            }
            Status = "Processed";
            return true;
        }

        // Bug: Cancel doesn't restock items
        public bool Cancel()
        {
            if (Status == "Shipped") return false;
            Status = "Cancelled";
            return true;
        }
    }

    // Bug: SQL injection, no parameterized queries
    public class DatabaseManager : IDisposable
    {
        private SqlConnection _connection;
        private bool _disposed = false;

        public DatabaseManager()
        {
            _connection = new SqlConnection(AppConfig.DbConnectionString);
        }

        public void Connect() => _connection.Open();

        // Bug: SQL injection via string concatenation
        public Product GetProduct(string productId)
        {
            var query = $"SELECT * FROM Products WHERE Id = '{productId}'";
            using var cmd = new SqlCommand(query, _connection);
            using var reader = cmd.ExecuteReader();
            if (reader.Read())
            {
                return new Product
                {
                    Id = reader.GetInt32(0),
                    Name = reader.GetString(1),
                    Price = reader.GetDouble(2),
                    StockQuantity = reader.GetInt32(3),
                    Category = reader.GetString(4)
                };
            }
            return null;
        }

        // Bug: SQL injection
        public List<Product> SearchProducts(string searchTerm)
        {
            var products = new List<Product>();
            var query = $"SELECT * FROM Products WHERE Name LIKE '%{searchTerm}%'";
            using var cmd = new SqlCommand(query, _connection);
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                products.Add(new Product
                {
                    Id = reader.GetInt32(0),
                    Name = reader.GetString(1),
                    Price = reader.GetDouble(2)
                });
            }
            return products;
        }

        // Bug: SQL injection in DELETE
        public void DeleteProduct(string productId)
        {
            var query = $"DELETE FROM Products WHERE Id = '{productId}'";
            using var cmd = new SqlCommand(query, _connection);
            cmd.ExecuteNonQuery();
        }

        // Bug: Incomplete Dispose pattern
        public void Dispose()
        {
            if (!_disposed)
            {
                _connection?.Close();
                _disposed = true;
            }
            // Missing GC.SuppressFinalize
        }
    }

    public class InventoryManager
    {
        private Dictionary<int, Product> _products = new Dictionary<int, Product>();
        private Dictionary<string, User> _users = new Dictionary<string, User>();
        private List<Order> _orders = new List<Order>();

        public bool AddProduct(Product product)
        {
            if (_products.ContainsKey(product.Id))
            {
                Console.WriteLine($"Product {product.Id} already exists");
                return false;
            }
            _products[product.Id] = product;
            return true;
        }

        // Bug: No null check on name parameter
        public List<Product> FindProducts(string name)
        {
            return _products.Values
                .Where(p => p.Name.ToLower().Contains(name.ToLower()))
                .ToList();
        }

        public User RegisterUser(string username, string password, string email)
        {
            if (_users.ContainsKey(username)) return null;
            var user = new User
            {
                Username = username,
                Password = password,                 // Stored as plain text
                Email = email,
                Role = "customer"
            };
            _users[username] = user;
            return user;
        }

        public User Authenticate(string username, string password)
        {
            if (!_users.TryGetValue(username, out var user)) return null;
            if (user.IsLocked)
            {
                Console.WriteLine("Account locked");
                return null;
            }
            if (user.CheckPassword(password))
            {
                user.LoginAttempts = 0;
                return user;
            }
            user.LoginAttempts++;
            if (user.LoginAttempts >= 5) user.IsLocked = true;
            return null;
        }

        public Order CreateOrder(string username, List<(int ProductId, int Qty)> items)
        {
            if (!_users.TryGetValue(username, out var user))
                throw new Exception($"User '{username}' not found");
            var orderItems = new List<(Product, int)>();
            foreach (var (pid, qty) in items)
            {
                if (!_products.TryGetValue(pid, out var product))
                    throw new Exception($"Product '{pid}' not found");
                orderItems.Add((product, qty));
            }
            var order = new Order(user, orderItems);
            if (order.Process())
            {
                _orders.Add(order);
                user.OrderHistory.Add(order);
                return order;
            }
            return null;
        }

        public double GetTotalRevenue()
        {
            double total = 0;
            foreach (var order in _orders)
                total += order.Total;
            return total;
        }
    }

    // Bug: Uses MD5 for hashing
    public static class SecurityHelper
    {
        public static string HashPassword(string password)
        {
            using var md5 = MD5.Create();            // MD5 is broken
            var bytes = md5.ComputeHash(Encoding.UTF8.GetBytes(password));
            return Convert.ToBase64String(bytes);
        }

        // Bug: Weak encryption, hardcoded key, zero IV
        public static string Encrypt(string plainText)
        {
            var key = Encoding.UTF8.GetBytes(AppConfig.EncryptionKey);
            using var aes = Aes.Create();
            aes.Key = key;
            aes.IV = new byte[16];                   // Zero IV is insecure
            using var encryptor = aes.CreateEncryptor();
            var plainBytes = Encoding.UTF8.GetBytes(plainText);
            var encrypted = encryptor.TransformFinalBlock(plainBytes, 0, plainBytes.Length);
            return Convert.ToBase64String(encrypted);
        }

        // Bug: Returns true for empty strings
        public static bool ValidateInput(string input)
        {
            if (string.IsNullOrEmpty(input)) return true;
            return input.Length <= 1000;
        }
    }

    // Bug: HttpClient created per request
    public class ApiClient
    {
        public async Task<string> GetDataAsync(string url)
        {
            using var client = new HttpClient();
            client.DefaultRequestHeaders.Add("Authorization", AppConfig.ApiKey);
            var response = await client.GetAsync(url);
            return await response.Content.ReadAsStringAsync();
        }

        // Bug: Swallows all exceptions
        public async Task<string> PostDataAsync(string url, string jsonBody)
        {
            try
            {
                using var client = new HttpClient();
                var content = new StringContent(jsonBody, Encoding.UTF8, "application/json");
                var response = await client.PostAsync(url, content);
                return await response.Content.ReadAsStringAsync();
            }
            catch (Exception)
            {
                return null;
            }
        }
    }

    public class ReportGenerator
    {
        private readonly InventoryManager _manager;
        public ReportGenerator(InventoryManager manager) => _manager = manager;

        // Bug: Doesn't escape commas in CSV values
        public void ExportToCsv(List<Product> products, string filePath)
        {
            using var writer = new StreamWriter(filePath);
            writer.WriteLine("Id,Name,Price,Stock,Category");
            foreach (var p in products)
                writer.WriteLine($"{p.Id},{p.Name},{p.Price},{p.StockQuantity},{p.Category}");
        }

        // Bug: String concatenation for path instead of Path.Combine
        public void SaveReport(string directory, string filename)
        {
            var path = directory + "\\" + filename;
            File.WriteAllText(path, "report content");
        }
    }

    // Bug: Mutable static state, not thread-safe
    public static class Logger
    {
        private static List<string> _logs = new List<string>();

        public static void Log(string message)
        {
            _logs.Add($"[{DateTime.Now}] {message}");
            Console.WriteLine(message);
        }

        // Bug: Exposes internal mutable list
        public static List<string> GetLogs() => _logs;
    }

    public static class Utilities
    {
        // Bug: Returns 0 on division by zero
        public static double SafeDivide(double a, double b)
        {
            if (b == 0) return 0;
            return a / b;
        }

        // Bug: Can generate duplicate IDs
        public static string GenerateId()
        {
            var rng = new Random();
            return $"ID-{rng.Next(1000, 9999)}";
        }
    }

    class Program
    {
        static void Main(string[] args)
        {
            var manager = new InventoryManager();

            manager.AddProduct(new Product(1, "Laptop Pro", 1299.99, 50, "Electronics"));
            manager.AddProduct(new Product(2, "Wireless Mouse", 29.99, 200, "Electronics"));
            manager.AddProduct(new Product(3, "USB Cable", 12.99, 500, "Accessories"));
            manager.AddProduct(new Product(4, "Monitor 27\"", 449.99, 30, "Electronics"));
            manager.AddProduct(new Product(5, "Desk Lamp", 34.99, 75, "Office"));

            manager.RegisterUser("alice", "pass123", "alice@example.com");
            manager.RegisterUser("bob", "qwerty", "bob@test.com");

            var user = manager.Authenticate("alice", "pass123");
            if (user != null)
                Console.WriteLine($"Logged in as: {user.Username}");

            var order = manager.CreateOrder("alice", new List<(int, int)> { (1, 2), (2, 3) });
            if (order != null)
                Console.WriteLine($"Order {order.OrderId}: ${order.Total:F2}");

            Console.WriteLine($"Revenue: ${manager.GetTotalRevenue():F2}");
            var hash = SecurityHelper.HashPassword("password123");
            Console.WriteLine($"Hash: {hash}");
            Console.WriteLine("Done.");
        }
    }
}
