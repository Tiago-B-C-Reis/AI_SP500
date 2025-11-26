import json

# some JSON:
x = '{ "name":"John", "age":30, "city":"New York"}'
xx = json.dumps(x)
print("x", type(x))
print("xx", type(xx))

a = [
     {"no":1,"s":"AAPL","n":"Apple Inc.","marketCap":3863453200570,"price":255.59,"change":-1.32,"revenue":391035000000},
     {"no":2,"s":"NVDA","n":"NVIDIA Corporation","marketCap":3355374900000,"price":137.01,"change":-2.09,"revenue":113269000000},
     {"no":3,"s":"MSFT","n":"Microsoft Corporation","marketCap":3200939220491.28,"price":430.53,"change":-1.73,"revenue":254190000000},
     {"no":4,"s":"GOOG","n":"Alphabet Inc.","marketCap":2366658680000,"price":194.04,"change":-1.55,"revenue":339859000000},
     {"no":5,"s":"GOOGL","n":"Alphabet Inc.","marketCap":2359575160000,"price":192.76,"change":-1.45,"revenue":339859000000},
     {"no":6,"s":"AMZN","n":"Amazon.com, Inc.","marketCap":2352733713040,"price":223.75,"change":-1.45,"revenue":620128000000},
     {"no":7,"s":"META","n":"Meta Platforms, Inc.","marketCap":1514213466978.73,"price":599.81,"change":-.59,"revenue":156227000000},
     {"no":8,"s":"TSLA","n":"Tesla, Inc.","marketCap":1385654352403.9402,"price":431.66,"change":-4.95,"revenue":97150000000},
     {"no":9,"s":"AVGO","n":"Broadcom Inc.","marketCap":1133168350713,"price":241.75,"change":-1.47,"revenue":51574000000},
     {"no":10,"s":"BRK.B","n":"Berkshire Hathaway Inc.","marketCap":984502628524,"price":456.51,"change":-.56,"revenue":369893000000},
     {"no":503,"s":"AMTM","n":"Amentum Holdings, Inc.","marketCap":4982828503.04,"price":20.48,"change":-.53,"revenue":8388000000}
     ]
aa = json.dumps(a)


y = '{"no":1,"s":"AAPL","n":"Apple Inc.","marketCap":3863453200570,"price":255.59,"change":-1.32,"revenue":391035000000},{"no":2,"s":"NVDA","n":"NVIDIA Corporation","marketCap":3355374900000,"price":137.01,"change":-2.09,"revenue":113269000000},{"no":3,"s":"MSFT","n":"Microsoft Corporation","marketCap":3200939220491.28,"price":430.53,"change":-1.73,"revenue":254190000000},{"no":4,"s":"GOOG","n":"Alphabet Inc.","marketCap":2366658680000,"price":194.04,"change":-1.55,"revenue":339859000000},{"no":5,"s":"GOOGL","n":"Alphabet Inc.","marketCap":2359575160000,"price":192.76,"change":-1.45,"revenue":339859000000},{"no":6,"s":"AMZN","n":"Amazon.com, Inc.","marketCap":2352733713040,"price":223.75,"change":-1.45,"revenue":620128000000},{"no":7,"s":"META","n":"Meta Platforms, Inc.","marketCap":1514213466978.73,"price":599.81,"change":-.59,"revenue":156227000000},{"no":8,"s":"TSLA","n":"Tesla, Inc.","marketCap":1385654352403.9402,"price":431.66,"change":-4.95,"revenue":97150000000},{"no":9,"s":"AVGO","n":"Broadcom Inc.","marketCap":1133168350713,"price":241.75,"change":-1.47,"revenue":51574000000},{"no":10,"s":"BRK.B","n":"Berkshire Hathaway Inc.","marketCap":984502628524,"price":456.51,"change":-.56,"revenue":369893000000},{"no":503,"s":"AMTM","n":"Amentum Holdings, Inc.","marketCap":4982828503.04,"price":20.48,"change":-.53,"revenue":8388000000}'
yy = json.dumps(y)
print("y", type(y))
print("yy", type(yy))


# parse x:
outa = json.loads(aa)
print("outa", type(outa))
outx = json.loads(x)
outxx = json.loads(xx)
#outy = json.loads(y)
outyy = json.loads(yy)
print("outx", type(outx))
print("outxx", type(outxx))
#print("outy", type(outyy))
print("outyy", type(outyy))



# the result is a Python dictionary:
#print(out1["age"])
#print(out2)
