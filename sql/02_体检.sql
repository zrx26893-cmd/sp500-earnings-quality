-- =====================================================================
-- 第 2 步：数据体检
-- 目的：原始数据离"一行 = 一家公司 × 一个财年"的干净表，还差什么？
-- 运行：在项目文件夹里  duckdb -no-agent < sql/02_体检.sql
-- =====================================================================


-- ① 表长什么样（4 步体检）-------------------------------------------

-- 1. 列名和类型
DESCRIBE SELECT * FROM 'data/raw/sec_raw.csv';

-- 2. 前 5 行
SELECT * FROM 'data/raw/sec_raw.csv' LIMIT 5;

-- 3. 抓了哪些会计科目（XBRL 标签），各有多少家公司
SELECT tag, COUNT(DISTINCT ticker) AS 公司数
FROM 'data/raw/sec_raw.csv'
GROUP BY tag
ORDER BY 公司数 DESC;

-- 4. 每列的统计摘要（看 null_percentage）
SUMMARIZE SELECT * FROM 'data/raw/sec_raw.csv';


-- 拿苹果当小例子 ------------------------------------------------------

-- 苹果 FY2009 那份年报里有 8 行：3 年净利润 + 3 年经营现金流 + 2 年总资产
-- 发现：fy = "哪一份年报"，不是"哪一年的数据"；资产是时点数（没有 start）
SELECT tag, start, "end", value, fy, filed
FROM 'data/raw/sec_raw.csv'
WHERE ticker = 'AAPL' AND fy = 2009
ORDER BY tag, "end";


-- ② 公司数对不对 ------------------------------------------------------

-- 名单 503 个代码，SEC 数据里 500 个代码、497 个 CIK
SELECT COUNT(DISTINCT ticker) AS 代码数, COUNT(DISTINCT cik) AS CIK数
FROM 'data/raw/sec_raw.csv';

-- 名单里有、SEC 数据里没有的公司（结果：XOM、HONA、VYLR）
-- HONA、VYLR：2026 年分拆，还没交过 10-K
-- XOM：2026-07 新设控股公司，换了新 CIK；历史年报在老 CIK 0000034088 下
SELECT DISTINCT p2.代码, p2.公司, p2.加入日期, p2.CIK AS list_cik, p1.cik AS sec_cik
FROM 'data/raw/sec_raw.csv' AS p1
RIGHT JOIN 'data/raw/sp500_list.csv' AS p2
  ON p1.cik = p2.CIK
WHERE p1.cik IS NULL;

-- 一个 CIK 对应两个代码的公司（结果：GOOGL/GOOG、FOXA/FOX、NWSA/NWS）
-- 同一家公司发了两类股票，财报是同一份 → 清洗时按 CIK 去重
SELECT CIK,
       COUNT(*) AS 代码个数,
       STRING_AGG(代码, ', ') AS 代码们,
       MIN(公司) AS 公司
FROM 'data/raw/sp500_list.csv'
GROUP BY CIK
HAVING COUNT(*) > 1;


-- ③④ 重复和年份：期间是不是一整年 ------------------------------------

-- 苹果净利润有 142 行，按道理 18 份年报 × 3 年 ≈ 54 行
-- 发现：10-K 里夹着季度数据（约 90 天）
SELECT start, "end", "end" - start AS 天数, value, fy
FROM 'data/raw/sec_raw.csv'
WHERE ticker = 'AAPL' AND tag = 'NetIncomeLoss'
ORDER BY "end";

-- 全表按期间长度分三类，并检查三类加起来 = 总行数
-- 结果：约一年 74,714 / 时点 17,236 / 其他 49,973（约 35%，多为季度）/ 差 = 0
SELECT SUM(CASE WHEN type = '约一年' THEN 1 ELSE 0 END) AS 一年,
       SUM(CASE WHEN type = '时点数' THEN 1 ELSE 0 END) AS 时点,
       SUM(CASE WHEN type = '其他'   THEN 1 ELSE 0 END) AS 其他,
       COUNT(*) AS 合计,
       COUNT(*) - ( SUM(CASE WHEN type = '约一年' THEN 1 ELSE 0 END)
                  + SUM(CASE WHEN type = '时点数' THEN 1 ELSE 0 END)
                  + SUM(CASE WHEN type = '其他'   THEN 1 ELSE 0 END) ) AS 差
FROM (
    SELECT CASE WHEN start IS NULL THEN '时点数'
                WHEN "end" - start BETWEEN 350 AND 380 THEN '约一年'
                ELSE '其他'
           END AS type
    FROM 'data/raw/sec_raw.csv'
) AS t;


-- ⑤ 有没有缺的、⑥ 数字对不对：下次做 -----------------------------------


-- =====================================================================
-- 问题清单（第 3 步清洗时逐条处理）
-- 1. HONA、VYLR：2026 年分拆，没有 10-K → 剔除
-- 2. XOM：换了 CIK → 用老 CIK 0000034088 补抓
-- 3. GOOGL/GOOG、FOXA/FOX、NWSA/NWS：一家公司两个代码 → 按 CIK 去重
-- 4. 10-K 里约 35% 的行不是全年数据 → 只留 350–380 天的
-- 5. 资产是时点数，没有 start → 单独处理
-- 6. fy ≠ 数据年份 → 按 "end" 定年份
-- =====================================================================
