import yfinance as yf
import pandas as pd
import os
from datetime import datetime, timedelta

def download_and_save_forex_data():
    if not os.path.exists('../data'):
        os.makedirs('../data')
    
    print("Downloading GBPJPY data...")
    
    # Get dates for last month
    end_date = datetime.now()
    start_date = end_date - timedelta(days=30)
    
    try:
        df = yf.download("GBPJPY=X", 
                        start=start_date.date(),
                        end=end_date.date(),
                        interval="1h",
                        progress=True)
        
        df['Datetime'] = df.index
        file_path = '../data/GBP_JPY_H1.csv'
        df.to_csv(file_path)
        print(f"Data saved to {file_path}")
        print(f"Downloaded {len(df)} rows of data")
    except Exception as e:
        print(f"Error downloading data: {e}")

if __name__ == "__main__":
    download_and_save_forex_data() 