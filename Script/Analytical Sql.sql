use [Online Retail]
--monthly sales growth--
select year(InvoiceDate) as Year
,month(InvoiceDate) as Month
,sum(abs(Quantity * UnitPrice)) as TotalSales
,lag(sum(abs(Quantity * UnitPrice))) over (order by year(InvoiceDate), month(InvoiceDate)) as PriorMonthSales
,((sum(abs(Quantity * UnitPrice)) - lag(sum(abs(Quantity * UnitPrice))) over (order by year(InvoiceDate), month(InvoiceDate))) 
/ lag(sum(abs(Quantity * UnitPrice))) over (order by year(InvoiceDate), month(InvoiceDate))) * 100 as MonthlySalesGrowth
from OnlineRetail
where InvoiceDate is not null
group by year(InvoiceDate), month(InvoiceDate)
order by Year, Month

-- monthly sales growth for each product --
select StockCode as Product_ID
,Description as Product_Name
,year(InvoiceDate) as Year
,month(InvoiceDate) as Month
,sum(abs(Quantity * UnitPrice)) as TotalSales
,((sum(abs(Quantity * UnitPrice)) - lag(sum(Quantity * UnitPrice)) over (partition by StockCode order by year(InvoiceDate), month(InvoiceDate)))
     / nullif(lag(sum(Quantity * UnitPrice)) over (partition by StockCode order by year(InvoiceDate), month(InvoiceDate)), 0)) * 100 as MonthlySalesGrowth
from OnlineRetail
where InvoiceDate is not null and  Description is not null
group by StockCode , Description, year(InvoiceDate), month(InvoiceDate)
order by StockCode , Description, Year, Month

-- Sales volume by Country -- 
select Country
,sum(abs(Quantity * UnitPrice)) as TotalSales
,(sum(abs(Quantity * UnitPrice)) * 100.0) / sum(sum(abs(Quantity * UnitPrice))) over () as SalesVolume
from OnlineRetail
where InvoiceDate is not null and Country is not null
group by Country
order by SalesVolume desc



-- Monthly Churn Rate --
with MonthlyChurn AS (
    select Year(cast(last_order as date)) as Year
	,month(cast(last_order as date)) as Month
	,count(distinct CustomerID) as TotalCustomers
	,sum(case when Segment IN ('Lost', 'Hibernating') then 1 else 0 end) as ChurnedCustomers
    from CustomerSegmentations
    group by Year(cast(last_order as date)) ,month(cast(last_order as date)) 
)

select Year , Month
,TotalCustomers
,ChurnedCustomers
,(ChurnedCustomers * 1.0 / nullif(TotalCustomers, 0)) * 100 AS ChurnRate
from MonthlyChurn
order by Year , Month;



-- Customer Segmentation Task --
/*
CREATE TABLE Segments (
    GroupName VARCHAR(50),
    RecencyScore INT,
    AvgFrequencyMonetaryScore INT
);

insert into Segments (GroupName, RecencyScore, AvgFrequencyMonetaryScore)
values
    ('Champions', 5, 5),
    ('Champions', 5, 4),
    ('Champions', 4, 5),
    
    ('Potential Loyalists', 5, 2),
    ('Potential Loyalists', 4, 2),
    ('Potential Loyalists', 4, 3),
    ('Potential Loyalists', 3, 3),
    
    ('Loyal Customers', 5, 3),
    ('Loyal Customers', 4, 4),
    ('Loyal Customers', 3, 5),
    ('Loyal Customers', 3, 4),
    
    ('Recent Customers', 5, 1),
    
    ('Promising', 4, 1),
    ('Promising', 3, 1),
    
    ('Customers Needing Attention', 3, 2),
    ('Customers Needing Attention', 2, 3),
    ('Customers Needing Attention', 2, 2),
	('Customers Needing Attention', 2, 1),

    
    ('At Risk', 2, 5),
    ('At Risk', 2, 4),
    ('At Risk', 1, 3),
    
    ('Cant Lose Them', 1, 5),
    ('Cant Lose Them', 1, 4),
    
    ('Hibernating', 1, 2),
    
    ('Lost', 1, 1);
	*/

with  CustomerActivityOverview as 
(
	select CustomerID
		, abs(sum(Quantity * UnitPrice)) as amount 
		, max(format(InvoiceDate , 'dd-MM-yyyy')) as last_order 
		, min(format(InvoiceDate , 'dd-MM-yyyy')) as first_order  
		, format(max(max(InvoiceDate)) over () , 'dd-MM-yyyy' ) as MostRecentOrderDate
		, datediff(day, max(InvoiceDate), max(max(InvoiceDate)) over ()) as DaysofAbsence
		, count(distinct(InvoiceNo)) as NumOfOrders
	from OnlineRetail
	where CustomerID is not null and InvoiceDate is not null and UnitPrice is not null 
	group by CustomerID
)
, ranges as (
	select cast(ceiling( max(amount) / 5.0 ) as int) as AmountRange 
	     ,cast (ceiling( max(DaysofAbsence) / 5.0 ) as int ) as DaysRange
		 ,cast (ceiling( max(NumOfOrders) / 5.0 ) as int ) as OrdersRange
	from CustomerActivityOverview
) , CustomerCategrization as 
(
	select c.CustomerID 
		, c.last_order
		, 5 - ((DaysofAbsence - 1 ) / r.DaysRange ) as recency
		, ntile(5) over (order by  amount) as monetary
		, case when NumOfOrders < 3 then 1
			   when NumOfOrders < 5 then 2
			   when NumOfOrders < 7 then 3
			   when NumOfOrders <=10 then 4
			   else 5
		  end as Frequency
	from  CustomerActivityOverview c , ranges r
) 
select  c.CustomerID , c.last_order , c.recency , cast( ceiling ((c.Frequency + c.monetary) / 2.0 ) as int ) as avg_Freq_mon,   s.GroupName as Segment
from CustomerCategrization c left join Segments s 
on c.recency = s.RecencyScore and cast( ceiling ((c.Frequency + c.monetary) / 2.0 ) as int ) = s.AvgFrequencyMonetaryScore
order by Segment , recency desc , avg_Freq_mon desc 

