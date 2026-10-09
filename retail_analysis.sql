ALTER TABLE online_retail_cleaned
RENAME COLUMN "Customer ID" TO Customer_ID;

-- Finding the count of rows.
SELECT count(*) FROM online_retail_cleaned ; -- 541910


-- Finding the count of how many NULL values are there.
SELECT count(*) FROM online_retail_cleaned WHERE Customer_ID is NULL; -- 135080
SELECT count(*) FROM online_retail_cleaned WHERE StockCode is NULL ; -- 0
SELECT count(*) FROM online_retail_cleaned  WHERE Description is NULL ; -- 1454
SELECT count(*) FROM online_retail_cleaned  WHERE InvoiceDate is NULL ; -- 0
SELECT count(*) FROM online_retail_cleaned  WHERE Quantity is NULL ; -- 0
SELECT count(*) FROM online_retail_cleaned  WHERE Price is NULL; -- 0

-- Finding the count negetive values 
 SELECT count(*) FROM online_retail_cleaned  	WHERE Quantity < 0; -- 10624
 SELECT count(*) FROM online_retail_cleaned  WHERE Price < 0; -- 2
 SELECT * FROM online_retail_cleaned  WHERE Price < 0; 
 
-- Now checking the earliest and latest invoice date. It is to confirm that date conversion python worked and to get an idea of time span of this dataset.
SELECT min(InvoiceDate), max(InvoiceDate) FROM online_retail_cleaned; -- min: 2010-12-01 08:26:00 and max: 2011-12-09 12:50:00

-- checking count of cancelled invoices
SELECT count(*) FROM online_retail_cleaned WHERE Invoice like 'C%'; -- 9288

-- checking the count of negetive quantity but not cancelled invoice
SELECT count(*) FROM online_retail_cleaned WHERE Quantity < 0 AND Invoice NOT like 'C%'; -- 1336
SELECT * FROM online_retail_cleaned WHERE Quantity < 0 AND Invoice NOT like 'C%'; -- 1336

-- checking that if quantity and price have rows wich contain 0
SELECT count(*) FROM online_retail_cleaned WHERE Quantity = 0; -- 0
SELECT count(*) FROM online_retail_cleaned WHERE Price = 0; -- 2515
SELECT * FROM online_retail_cleaned WHERE Price = 0; 

-- counting distinc number of invoices, products, and customer are there
SELECT count(DISTINCT Invoice) FROM online_retail_cleaned ; -- 25900
SELECT count(DISTINCT StockCode) FROM online_retail_cleaned ;-- 4070
SELECT count(DISTINCT Customer_ID) FROM online_retail_cleaned ;-- 4372


-- CLEANING THE DATSET AND CREATING NEW TABLE WITH CLEAT DATABASE
-- the NOT EXISTS check below looks up cancellations once for every sale row.
-- Without an index SQLite scans the whole table each time, which can take very long on 540K rows.
-- The index lets it jump straight to the rows for that customer and product.
CREATE INDEX IF NOT EXISTS idx_retail_cancel ON online_retail_cleaned (Customer_ID, StockCode);

-- creating a new table with revenue column also 
-- WHY: some large sales were cancelled shortly after. Example: invoice 581483 sold 80995 units
-- (168469.60) and invoice C581484 reversed the same quantity 12 minutes later, for the same customer.
-- The Quantity > 0 filter removes the cancellation row, but the original sale stayed in the table
-- and counted as real revenue. That made a ghost product the top seller, inflated January and
-- December 2011 revenue, and would have made fake "Champions" in the RFM step.
-- the NOT EXISTS block drops any sale that has a matching later cancellation
-- (same customer, same product, exactly opposite quantity, cancellation on or after the sale date).
-- Known limitations: partial returns are not netted out, and a repeat purchase of the same
-- quantity could be matched wrongly. Both effects are small.
CREATE TABLE clean_retail_dataset AS 
SELECT o.*, (o.Quantity * o.Price) AS Revenue
FROM online_retail_cleaned o
WHERE o.StockCode NOT IN ('BANK CHARGES', 'DOT', 'M', 'POST','C2', 'PADS')
  AND o.Customer_ID IS NOT NULL
  AND o.Quantity > 0
  AND o.Price > 0
  AND NOT EXISTS (
        SELECT 1
        FROM online_retail_cleaned c
        WHERE c.Customer_ID = o.Customer_ID   -- same customer
          AND c.StockCode   = o.StockCode     -- same product
          AND c.Quantity    = -o.Quantity     -- exactly the opposite quantity
          AND c.Invoice LIKE 'C%'             -- it is a cancellation
          AND c.InvoiceDate >= o.InvoiceDate  -- it happened on or after the sale, not before
  );

--counting the number of rows droped and there percentage.
-- WHY: same filters as the CREATE TABLE above, so the dropped count and percentage match the real table.
SELECT (
(SELECT count(*) FROM online_retail_cleaned ) - count(*)) AS counts, (100.00 - (count(*) * 100.0 / 
(SELECT count(*) FROM online_retail_cleaned ))) AS percentage
FROM online_retail_cleaned o
WHERE o.StockCode NOT IN ('BANK CHARGES', 'DOT', 'M', 'POST','C2', 'PADS')
  AND o.Customer_ID IS NOT NULL
  AND o.Quantity > 0
  AND o.Price > 0
  AND NOT EXISTS (
        SELECT 1
        FROM online_retail_cleaned c
        WHERE c.Customer_ID = o.Customer_ID
          AND c.StockCode   = o.StockCode
          AND c.Quantity    = -o.Quantity
          AND c.Invoice LIKE 'C%'
          AND c.InvoiceDate >= o.InvoiceDate
  ); --count: 149551, percentage: 27.59 (before the reversed-sales fix it was count: 145573, percentage: 26.86)
-- The individual counts (cancellations, NULL Customer_ID, negative Quantity, zero Price)
-- do not add up to the total dropped, because the problems overlap.
-- For example, most rows with Price = 0 also have a NULL Customer_ID,
-- so those rows were counted in more than one check.

-- Checking
SELECT count(*) FROM clean_retail_dataset; -- 392359 (was 396337 before the reversed-sales fix)
SELECT count(*) FROM clean_retail_dataset WHERE Customer_ID is NULL;-- 0
-- FIX: added the missing semicolon (it goes before the comment).
SELECT count(*) FROM clean_retail_dataset WHERE Invoice like 'C%'; -- 0 (its 0 because all the cancelation have Quantity in negetive value when i removed that it removed it as well)
SELECT count(*) FROM clean_retail_dataset WHERE Quantity < 0 AND Invoice NOT like 'C%';-- 0
SELECT count(*) FROM clean_retail_dataset WHERE Price = 0; -- 0
SELECT DISTINCT StockCode, Description, price, Quantity FROM clean_retail_dataset WHERE StockCode NOT IN ('BANK CHARGES', 'DOT', 'M', 'POST','C2', 'PADS') ; -- Sanity check: normal products only
-- WHY: confirm the two ghost orders are gone (should return no rows).
SELECT * FROM clean_retail_dataset WHERE Invoice IN ('581483', '541431'); -- no rows returned
-- WHY: total revenue should be lower than before the fix (was 8761066.65).
SELECT ROUND(SUM(Revenue), 2) FROM clean_retail_dataset; -- 8284415.21
-- WHY: customer 12346 may be gone after the fix, so recount instead of reusing the old number.
SELECT count(DISTINCT Customer_ID) FROM clean_retail_dataset; -- 4324
--Checking Passed


-- MONTHLY REVENUE 
-- What is the total revenue for each month, total number of distinct customer in that month, total number of order in that month and Average Revenue for each Month
SELECT strftime('%Y-%m', InvoiceDate) AS InvoiceMonth, sum(Revenue) AS TotalRevenue, count(Distinct Customer_ID) AS customers, count(DISTINCT Invoice) AS orders, ROUND(SUM(Revenue) / COUNT(DISTINCT Invoice), 2) AS AvgOrderValue
 FROM clean_retail_dataset GROUP BY strftime('%Y-%m', InvoiceDate) ORDER BY InvoiceMonth;

 -- Finding out wich month has the highest Revenue and Wich month has the lowest Revenue. 
 SELECT strftime('%Y-%m', InvoiceDate) AS InvoiceMonth, sum(Revenue) AS TotalRevenue
 FROM clean_retail_dataset GROUP BY strftime('%Y-%m', InvoiceDate) ORDER BY TotalRevenue DESC LIMIT 1 ;
 
 SELECT strftime('%Y-%m', InvoiceDate) AS InvoiceMonth, sum(Revenue) AS TotalRevenue
 FROM clean_retail_dataset GROUP BY strftime('%Y-%m', InvoiceDate) ORDER BY TotalRevenue ASC LIMIT 1 ;
 
-- 2011-12 revenue is much lower than the previous month because the dataset ends on 2011-12-09.
-- the "20 to 27 days" claim was not checked, so the comment now points to the SalesDays column instead.
-- It has sales on only 8 days (the other months have sales on many more days, see the SalesDays column), so it is a partial month and not a real drop in sales.
 SELECT strftime('%Y-%m', InvoiceDate) AS InvoiceMonth, sum(Revenue) AS TotalRevenue, COUNT(DISTINCT date(InvoiceDate)) AS SalesDays
 FROM clean_retail_dataset GROUP BY strftime('%Y-%m', InvoiceDate) ORDER BY InvoiceMonth DESC;
 
 -- TOP PRODUCTS AND COUNTRIES
 -- Seeing the top 10 products by Revenue.
SELECT StockCode, MAX(Description) AS Description, SUM(Revenue) AS TotalRevenue, SUM(Quantity) AS UnitsSold
FROM clean_retail_dataset GROUP BY StockCode ORDER BY TotalRevenue DESC LIMIT 10;
 
-- Top 10 products by unit Sold 
SELECT StockCode, MAX(Description) AS Description, SUM(Quantity) AS UnitsSold, SUM(Revenue) AS TotalRevenue
FROM clean_retail_dataset GROUP BY StockCode ORDER BY UnitsSold DESC LIMIT 10;

--For each country: revenue, number of customers, and percentage of total revenue.
SELECT Country, SUM(Revenue) AS TotalRevenue, COUNT(DISTINCT Customer_ID) AS Customers,ROUND( SUM(Revenue) * 100.0 /(SELECT SUM(Revenue) FROM clean_retail_dataset),2) AS RevenuePercentage
FROM clean_retail_dataset GROUP BY Country ORDER BY TotalRevenue DESC;

-- RFM
-- reference date for Recency.
SELECT date(max(InvoiceDate), '+1 day') AS ReferenceDate FROM clean_retail_dataset; -- 2011-12-10

-- one row per customer with Recency, Frequency and Monetary.
-- these three numbers say how recently, how often and how much each customer buys.
CREATE TABLE rfm AS
SELECT Customer_ID, CAST(julianday((SELECT date(max(InvoiceDate), '+1 day') FROM clean_retail_dataset)) - julianday(date(max(InvoiceDate))) AS INTEGER) AS Recency, COUNT(DISTINCT Invoice) AS Frequency, ROUND(SUM(Revenue), 2) AS Monetary
FROM clean_retail_dataset
GROUP BY Customer_ID;

-- the rfm table must have exactly one row per customer.
SELECT count(*) FROM rfm; -- 4324
SELECT count(DISTINCT Customer_ID) FROM clean_retail_dataset; -- 4324 (must match the line above)

-- scores from 1 to 5 with NTILE(5).
-- NTILE gives group 1 to the FIRST rows in the order, so the order decides the direction:
-- Recency: a smaller number is better, so we sort DESC (the longest-inactive customers get 1, the most recent get 5).
-- Frequency and Monetary: bigger is better, so we sort ASC (the smallest get 1, the biggest get 5).
DROP TABLE IF EXISTS rfm_scored;
CREATE TABLE rfm_scored AS
SELECT Customer_ID, Recency, Frequency, Monetary,
       NTILE(5) OVER (ORDER BY Recency DESC)  AS r_score,
       NTILE(5) OVER (ORDER BY Frequency ASC) AS f_score,
       NTILE(5) OVER (ORDER BY Monetary ASC)  AS m_score
FROM rfm;

-- SEGMENTS
-- Assign each customer a segment with CASE WHEN.
CREATE TABLE customer_segments AS
SELECT Customer_ID, Recency, Frequency, Monetary, r_score, f_score, m_score,
       CASE
         WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'      -- bought recently and often
         WHEN f_score >= 4 AND r_score >= 3 THEN 'Loyal'          -- buy often, a bit less recent
         WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'  -- bought recently, but only a few times
         WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'        -- used to buy often, but have gone quiet
         WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'           -- inactive for a long time and rarely bought
         ELSE 'Others'
       END AS Segment
FROM rfm_scored;

-- Summary per segment: customers, revenue, average revenue per customer, and the share of customers and revenue.
SELECT Segment,
       count(*) AS Customers,
       ROUND(SUM(Monetary), 2) AS TotalRevenue,
       ROUND(AVG(Monetary), 2) AS AvgRevenuePerCustomer,
       ROUND(count(*) * 100.0 / (SELECT count(*) FROM customer_segments), 2) AS PctCustomers,
       ROUND(SUM(Monetary) * 100.0 / (SELECT SUM(Monetary) FROM customer_segments), 2) AS PctRevenue
FROM customer_segments
GROUP BY Segment
ORDER BY TotalRevenue DESC;


SELECT Customer_ID, Recency, Frequency, Monetary, r_score, f_score, m_score, Segment
FROM customer_segments
ORDER BY Monetary DESC;

