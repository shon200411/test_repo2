-- ============================================================
-- E-Commerce Database Schema & Operations
-- ============================================================

CREATE DATABASE ECommerceDB;
GO
USE ECommerceDB;
GO

-- Users table - no index on email despite frequent lookups
CREATE TABLE Users (
    UserID INT IDENTITY(1,1),
    Username NVARCHAR(50),
    Password NVARCHAR(100),          -- Storing plain text passwords
    Email NVARCHAR(100),
    FirstName NVARCHAR(50),
    LastName NVARCHAR(50),
    Phone VARCHAR(20),
    Address NVARCHAR(MAX),           -- Using MAX unnecessarily
    City NVARCHAR(100),
    Country NVARCHAR(100),
    CreatedAt DATETIME DEFAULT GETDATE(),
    IsActive BIT DEFAULT 1,
    Role NVARCHAR(20) DEFAULT 'customer',
    LoginAttempts INT DEFAULT 0,
    PRIMARY KEY (UserID)
);

-- Products table - price stored as FLOAT (precision issues)
CREATE TABLE Products (
    ProductID INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(200),
    Description NVARCHAR(MAX),
    Price FLOAT,                     -- Should be DECIMAL for money
    Cost FLOAT,                      -- Should be DECIMAL for money
    StockQuantity INT,
    CategoryID INT,
    SupplierID INT,
    SKU VARCHAR(50),
    Weight FLOAT,
    IsActive BIT DEFAULT 1,
    CreatedAt DATETIME DEFAULT GETDATE(),
    UpdatedAt DATETIME
);

-- Orders table
CREATE TABLE Orders (
    OrderID INT IDENTITY(1,1) PRIMARY KEY,
    UserID INT,
    OrderDate DATETIME DEFAULT GETDATE(),
    Status VARCHAR(20) DEFAULT 'Pending',
    TotalAmount FLOAT,               -- Should be DECIMAL
    ShippingAddress NVARCHAR(MAX),
    PaymentMethod VARCHAR(50),
    PaymentStatus VARCHAR(20) DEFAULT 'Unpaid',
    Notes NVARCHAR(MAX),
    -- Missing foreign key constraint
);

-- Order items - no foreign keys defined
CREATE TABLE OrderItems (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT,                     -- No FK constraint
    ProductID INT,                   -- No FK constraint
    Quantity INT,
    UnitPrice FLOAT,                 -- Should be DECIMAL
    Discount FLOAT DEFAULT 0,
    LineTotal AS (Quantity * UnitPrice * (1 - Discount))
);

CREATE TABLE Categories (
    CategoryID INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName NVARCHAR(100),
    ParentCategoryID INT,
    Description NVARCHAR(500),
    IsActive BIT DEFAULT 1
);

CREATE TABLE ProductReviews (
    ReviewID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT,
    UserID INT,
    Rating INT,                      -- No CHECK constraint for 1-5
    ReviewText NVARCHAR(MAX),
    CreatedAt DATETIME DEFAULT GETDATE(),
    IsApproved BIT DEFAULT 0
);

CREATE TABLE InventoryLog (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    ProductID INT,
    ChangeType VARCHAR(20),
    QuantityChange INT,
    PreviousQuantity INT,
    NewQuantity INT,
    ChangedBy INT,
    ChangedAt DATETIME DEFAULT GETDATE(),
    Reason NVARCHAR(500)
);

CREATE TABLE Coupons (
    CouponID INT IDENTITY(1,1) PRIMARY KEY,
    Code VARCHAR(50),                -- No UNIQUE constraint
    DiscountPercent FLOAT,
    DiscountAmount FLOAT,
    MinOrderAmount FLOAT,
    MaxUses INT,
    CurrentUses INT DEFAULT 0,
    StartDate DATETIME,
    EndDate DATETIME,
    IsActive BIT DEFAULT 1
);


-- ── Stored Procedures ───────────────────────────────────────

-- Bug: SQL injection vulnerability via dynamic SQL
CREATE PROCEDURE sp_SearchProducts
    @SearchTerm NVARCHAR(200)
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX)
    SET @SQL = 'SELECT * FROM Products WHERE ProductName LIKE ''%' + @SearchTerm + '%'''
    EXEC(@SQL)                       -- SQL injection!
END
GO

-- Bug: SELECT * in production code
CREATE PROCEDURE sp_GetUserByID
    @UserID INT
AS
BEGIN
    SELECT * FROM Users WHERE UserID = @UserID
END
GO

-- Bug: No error handling, no transaction, no user validation
CREATE PROCEDURE sp_CreateOrder
    @UserID INT,
    @ShippingAddress NVARCHAR(MAX),
    @PaymentMethod VARCHAR(50)
AS
BEGIN
    DECLARE @OrderID INT
    INSERT INTO Orders (UserID, ShippingAddress, PaymentMethod)
    VALUES (@UserID, @ShippingAddress, @PaymentMethod)
    SET @OrderID = SCOPE_IDENTITY()
    SELECT @OrderID AS NewOrderID
END
GO

-- Bug: Cursor-based processing instead of set-based
CREATE PROCEDURE sp_UpdateAllPrices
    @IncreasePercent FLOAT
AS
BEGIN
    DECLARE @ProductID INT, @CurrentPrice FLOAT
    DECLARE price_cursor CURSOR FOR
        SELECT ProductID, Price FROM Products WHERE IsActive = 1
    OPEN price_cursor
    FETCH NEXT FROM price_cursor INTO @ProductID, @CurrentPrice
    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE Products
        SET Price = @CurrentPrice * (1 + @IncreasePercent / 100),
            UpdatedAt = GETDATE()
        WHERE ProductID = @ProductID
        FETCH NEXT FROM price_cursor INTO @ProductID, @CurrentPrice
    END
    CLOSE price_cursor
    DEALLOCATE price_cursor
END
GO

-- Bug: Password compared as plain text
CREATE PROCEDURE sp_AuthenticateUser
    @Username NVARCHAR(50),
    @Password NVARCHAR(100)
AS
BEGIN
    DECLARE @UserID INT, @IsActive BIT
    SELECT @UserID = UserID, @IsActive = IsActive
    FROM Users
    WHERE Username = @Username AND Password = @Password   -- Plain text!
    IF @UserID IS NOT NULL AND @IsActive = 1
    BEGIN
        UPDATE Users SET LoginAttempts = 0 WHERE UserID = @UserID
        SELECT @UserID AS UserID, 'Success' AS Result
    END
    ELSE
    BEGIN
        UPDATE Users SET LoginAttempts = LoginAttempts + 1
        WHERE Username = @Username
        SELECT NULL AS UserID, 'Failed' AS Result
    END
END
GO

-- Bug: SQL injection via string concatenation
CREATE PROCEDURE sp_GetUserOrders
    @Username NVARCHAR(50),
    @Status VARCHAR(20)
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX)
    SET @SQL = 'SELECT o.*, u.Username FROM Orders o '
             + 'JOIN Users u ON o.UserID = u.UserID '
             + 'WHERE u.Username = ''' + @Username + ''''
    IF @Status IS NOT NULL
        SET @SQL = @SQL + ' AND o.Status = ''' + @Status + ''''
    EXEC(@SQL)
END
GO

-- Bug: No stock validation, race condition, no negative check
CREATE PROCEDURE sp_AddOrderItem
    @OrderID INT, @ProductID INT, @Quantity INT
AS
BEGIN
    DECLARE @Price FLOAT
    SELECT @Price = Price FROM Products WHERE ProductID = @ProductID
    INSERT INTO OrderItems (OrderID, ProductID, Quantity, UnitPrice)
    VALUES (@OrderID, @ProductID, @Quantity, @Price)
    UPDATE Products SET StockQuantity = StockQuantity - @Quantity
    WHERE ProductID = @ProductID
    UPDATE Orders SET TotalAmount = (
        SELECT SUM(Quantity * UnitPrice * (1 - Discount))
        FROM OrderItems WHERE OrderID = @OrderID
    ) WHERE OrderID = @OrderID
END
GO

-- Bug: NULL comparison issues, can produce negative totals
CREATE PROCEDURE sp_ApplyCoupon
    @OrderID INT, @CouponCode VARCHAR(50)
AS
BEGIN
    DECLARE @DiscountPct FLOAT, @DiscountAmt FLOAT, @MinOrder FLOAT
    DECLARE @MaxUses INT, @CurrentUses INT, @OrderTotal FLOAT
    SELECT @DiscountPct = DiscountPercent, @DiscountAmt = DiscountAmount,
           @MinOrder = MinOrderAmount, @MaxUses = MaxUses, @CurrentUses = CurrentUses
    FROM Coupons WHERE Code = @CouponCode AND IsActive = 1
         AND GETDATE() BETWEEN StartDate AND EndDate
    SELECT @OrderTotal = TotalAmount FROM Orders WHERE OrderID = @OrderID
    IF @CurrentUses < @MaxUses AND @OrderTotal >= @MinOrder
    BEGIN
        DECLARE @Discount FLOAT
        IF @DiscountPct > 0
            SET @Discount = @OrderTotal * @DiscountPct / 100
        ELSE
            SET @Discount = @DiscountAmt
        UPDATE Orders SET TotalAmount = TotalAmount - @Discount WHERE OrderID = @OrderID
        UPDATE Coupons SET CurrentUses = CurrentUses + 1 WHERE Code = @CouponCode
    END
END
GO

-- Bug: SQL injection, no table/column validation
CREATE PROCEDURE sp_DynamicSearch
    @TableName NVARCHAR(100), @ColumnName NVARCHAR(100), @SearchValue NVARCHAR(200)
AS
BEGIN
    DECLARE @SQL NVARCHAR(MAX)
    SET @SQL = 'SELECT * FROM ' + @TableName
             + ' WHERE ' + @ColumnName + ' = ''' + @SearchValue + ''''
    EXEC(@SQL)
END
GO


-- ── Views ────────────────────────────────────────────────────

-- Bug: SELECT * in view
CREATE VIEW vw_AllOrders AS
    SELECT * FROM Orders o LEFT JOIN Users u ON o.UserID = u.UserID
GO

-- Bug: No schema binding, non-deterministic function
CREATE VIEW vw_ActiveProducts AS
    SELECT ProductID, ProductName, Price, StockQuantity,
           GETDATE() AS QueryTime
    FROM Products WHERE IsActive = 1
GO

-- Bug: Correlated subqueries instead of JOINs
CREATE VIEW vw_ProductSales AS
    SELECT p.ProductID, p.ProductName, p.Price,
        (SELECT COUNT(*) FROM OrderItems oi WHERE oi.ProductID = p.ProductID) AS TimesOrdered,
        (SELECT SUM(oi.Quantity) FROM OrderItems oi WHERE oi.ProductID = p.ProductID) AS TotalQtySold,
        (SELECT AVG(pr.Rating) FROM ProductReviews pr WHERE pr.ProductID = p.ProductID) AS AvgRating
    FROM Products p
GO

-- Bug: Exposes passwords
CREATE VIEW vw_UserPasswords AS
    SELECT UserID, Username, Password, Email FROM Users
GO


-- ── Queries with Issues ─────────────────────────────────────

-- Bug: NOLOCK causes dirty reads
SELECT o.OrderID, o.OrderDate, o.TotalAmount, u.Username
FROM Orders o WITH (NOLOCK)
JOIN Users u WITH (NOLOCK) ON o.UserID = u.UserID
WHERE o.Status = 'Pending'
ORDER BY o.OrderDate DESC
GO

-- Bug: NOT IN with nullable subquery
SELECT ProductID, ProductName FROM Products
WHERE ProductID NOT IN (SELECT ProductID FROM OrderItems)
GO

-- Bug: Implicit type conversion
SELECT * FROM Products
WHERE CategoryID = '5' AND Price > '100.00'
GO

-- Bug: Leading wildcard = full table scan
SELECT * FROM Users WHERE Email LIKE '%@gmail.com'
GO

-- Bug: Functions on columns prevent index usage
SELECT * FROM Orders WHERE YEAR(OrderDate) = 2024 AND MONTH(OrderDate) = 12
GO

-- Bug: SELECT DISTINCT to mask JOIN issues
SELECT DISTINCT u.UserID, u.Username, u.Email
FROM Users u JOIN Orders o ON u.UserID = o.UserID
JOIN OrderItems oi ON o.OrderID = oi.OrderID
GO

-- Bug: Correlated subquery per row
SELECT p.ProductName, p.Price,
    (SELECT TOP 1 o.OrderDate FROM Orders o
     JOIN OrderItems oi ON o.OrderID = oi.OrderID
     WHERE oi.ProductID = p.ProductID
     ORDER BY o.OrderDate DESC) AS LastOrderDate
FROM Products p WHERE p.IsActive = 1
GO


-- ── Data Manipulation Issues ────────────────────────────────

-- Bug: INSERT without column list
INSERT INTO Categories VALUES ('Electronics', NULL, 'Electronic devices', 1);
INSERT INTO Categories VALUES ('Clothing', NULL, 'Apparel and fashion', 1);
GO

-- Bug: Hardcoded credentials
INSERT INTO Users (Username, Password, Email, FirstName, LastName, Role)
VALUES ('admin', 'admin123', 'admin@company.com', 'System', 'Admin', 'admin');
INSERT INTO Users (Username, Password, Email, FirstName, LastName, Role)
VALUES ('superuser', 'P@ssw0rd!', 'super@company.com', 'Super', 'User', 'admin');
GO

-- Bug: No batch size for large updates
UPDATE Products SET Price = Price * 1.05, UpdatedAt = GETDATE()
WHERE CategoryID IN (SELECT CategoryID FROM Categories WHERE IsActive = 1)
GO

-- Bug: Large delete without batching
DELETE FROM InventoryLog WHERE ChangedAt < DATEADD(YEAR, -2, GETDATE())
GO

-- Bug: Granting excessive permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON Users TO public;
GRANT EXECUTE ON sp_DynamicSearch TO public;
GO


-- ── Triggers with Issues ────────────────────────────────────

-- Bug: Trigger doesn't handle multi-row inserts
CREATE TRIGGER tr_OrderInsert ON Orders AFTER INSERT
AS
BEGIN
    DECLARE @UserID INT, @OrderID INT
    SELECT @UserID = UserID, @OrderID = OrderID FROM inserted
    INSERT INTO InventoryLog (ProductID, ChangeType, ChangedBy, Reason)
    VALUES (NULL, 'ORDER_CREATED', @UserID, 'Order ' + CAST(@OrderID AS VARCHAR) + ' created')
END
GO

-- Bug: Recursive trigger possibility
CREATE TRIGGER tr_ProductUpdate ON Products AFTER UPDATE
AS
BEGIN
    UPDATE Products SET UpdatedAt = GETDATE()
    WHERE ProductID IN (SELECT ProductID FROM inserted)
END
GO


-- ── Functions with Issues ───────────────────────────────────

-- Bug: Scalar function (poor perf vs inline TVF)
CREATE FUNCTION fn_GetProductCount(@CategoryID INT)
RETURNS INT
AS
BEGIN
    DECLARE @Count INT
    SELECT @Count = COUNT(*) FROM Products
    WHERE CategoryID = @CategoryID AND IsActive = 1
    RETURN @Count
END
GO

CREATE FUNCTION fn_FormatCurrency(@Amount FLOAT)
RETURNS VARCHAR(20)
AS
BEGIN
    RETURN '$' + CAST(CAST(@Amount AS DECIMAL(10,2)) AS VARCHAR)
END
GO


-- ── Complex Queries ─────────────────────────────────────────

-- Bug: != instead of <>, FLOAT sum precision loss
SELECT DATENAME(MONTH, o.OrderDate) AS MonthName, YEAR(o.OrderDate) AS OrderYear,
    COUNT(o.OrderID) AS TotalOrders, SUM(o.TotalAmount) AS Revenue,
    AVG(o.TotalAmount) AS AvgOrderValue, COUNT(DISTINCT o.UserID) AS UniqueCustomers
FROM Orders o WHERE o.Status != 'Cancelled'
GROUP BY DATENAME(MONTH, o.OrderDate), YEAR(o.OrderDate)
ORDER BY OrderYear DESC, Revenue DESC
GO

-- Bug: HAVING used where WHERE should be
SELECT CategoryID, COUNT(*) AS ProductCount, AVG(Price) AS AvgPrice
FROM Products GROUP BY CategoryID
HAVING CategoryID IS NOT NULL
GO

-- Bug: UNION instead of UNION ALL (unnecessary sort)
SELECT UserID, Username, 'Active' AS Status FROM Users WHERE IsActive = 1
UNION
SELECT UserID, Username, 'Inactive' AS Status FROM Users WHERE IsActive = 0
GO

-- Bug: Multiple table scans in one query
SELECT
    (SELECT COUNT(*) FROM Users) AS TotalUsers,
    (SELECT COUNT(*) FROM Products) AS TotalProducts,
    (SELECT COUNT(*) FROM Orders) AS TotalOrders,
    (SELECT SUM(TotalAmount) FROM Orders WHERE Status = 'Completed') AS TotalRevenue
GO

-- Bug: Redundant and problematic indexes
CREATE INDEX IX_Orders_UserID ON Orders(UserID);
CREATE INDEX IX_Users_Everything ON Users(Username, Email, FirstName, LastName, City, Country);
CREATE INDEX IX_Products_IsActive ON Products(IsActive);  -- Low cardinality
GO

-- Bug: No TRY/CATCH, no transaction
CREATE PROCEDURE sp_TransferStock
    @FromProductID INT, @ToProductID INT, @Quantity INT
AS
BEGIN
    UPDATE Products SET StockQuantity = StockQuantity - @Quantity
    WHERE ProductID = @FromProductID
    UPDATE Products SET StockQuantity = StockQuantity + @Quantity
    WHERE ProductID = @ToProductID
END
GO

-- Bug: DROP without IF EXISTS
DROP TABLE TempReports;
DROP PROCEDURE sp_OldProcedure;
GO

-- Bug: Old-style JOIN syntax (deprecated)
SELECT * FROM Products p, Categories c WHERE p.CategoryID = c.CategoryID
GO

-- Bug: Magic numbers
SELECT * FROM Orders
WHERE TotalAmount > 500 AND DATEDIFF(DAY, OrderDate, GETDATE()) < 30
  AND UserID IN (SELECT UserID FROM Users WHERE LoginAttempts > 3)
GO

-- Bug: Unused variables, no inventory restore, no audit
CREATE PROCEDURE sp_ProcessReturns @OrderID INT
AS
BEGIN
    DECLARE @RefundAmount FLOAT
    DECLARE @CustomerName NVARCHAR(100)     -- Never used
    DECLARE @TempValue INT                  -- Never used
    SELECT @RefundAmount = TotalAmount FROM Orders WHERE OrderID = @OrderID
    UPDATE Orders SET Status = 'Returned' WHERE OrderID = @OrderID
END
GO

-- Bug: TOP 100 PERCENT is meaningless, hardcoded date
SELECT TOP 100 PERCENT *
FROM Orders o JOIN Users u ON o.UserID = u.UserID
JOIN OrderItems oi ON o.OrderID = oi.OrderID
JOIN Products p ON oi.ProductID = p.ProductID
WHERE o.OrderDate >= '2024-01-01'
ORDER BY o.OrderDate DESC
GO
