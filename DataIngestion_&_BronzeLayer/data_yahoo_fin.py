from yahoo_fin.stock_info import get_data

amazon_weekly = get_data("amzn", start_date="2009-12-04", end_date="2019-12-04", index_as_date=True, interval="1wk")

print(amazon_weekly)
