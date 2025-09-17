// Clear all data
clear all
set more off

// Import and clean exchange rate data
import delimited "ER_HongKongDollar_per_USDollar.csv", varnames(1) clear
rename close exchange_rate
gen date_hkd = date(date, "YMD")
format date_hkd %td
destring exchange_rate, replace ignore("null")
drop if missing(exchange_rate)
gen year_hkd = year(date_hkd)
keep if year_hkd >= 2010 & year_hkd <= 2020
tsset date_hkd
save "HKD_USD_cleaned.dta", replace

// Import and clean HSI data
import delimited "HSI.csv", varnames(1) clear
rename close YFK
gen date_YFK = date(date, "YMD")
format date_YFK %td
destring YFK, replace ignore("null")
drop if missing(YFK)
gen year = year(date_YFK)
keep if year >= 2010 & year <= 2020
tsset date_YFK
save "HSI_cleaned.dta", replace

// Import US 3-month Treasury yield data
import delimited "US_3monthTBill.csv", varname(1) clear
rename close tbill_rate  // Assume close column is the yield
gen date_tbr = date(date, "YMD")
format date_tbr %td
destring tbill_rate, replace ignore("null")
drop if missing(tbill_rate)
gen year = year(date_tbr)
keep if year >= 2010 & year <= 2020
tsset date_tbr
save "US_3monthTBill_cleaned.dta", replace

// Merge datasets on common dates
use "HSI_cleaned.dta", clear
merge 1:1 date using "HKD_USD_cleaned.dta"
keep if _merge == 3  // Keep only common dates
drop _merge
merge 1:1 date using "US_3monthTBill_cleaned.dta"
keep if _merge == 3  // Keep only common dates
drop _merge
save "Merged_data.dta", replace

// Plot time series
tsline YFK, title("HSI Close Price (2010-2020)") xtitle("Date") ytitle("HSI Close Price")
graph export "HSI_Close_Price_TimeSeries.png", replace

tsline exchange_rate, title("HKD/USD Exchange Rate (2010-2020)") xtitle("Date") ytitle("Exchange Rate")
graph export "HKD_USD_Exchange_Rate_TimeSeries.png", replace

tsline tbill_rate, title("US 3-Month Treasury Bill Rate (2010-2020)") xtitle("Date") ytitle("T-Bill Rate")
graph export "US_3Month_TBill_Rate_TimeSeries.png", replace

//descriptive statistics
summarize YFK exchange_rate tbill_rate

//Unit root test (ADF) and deal with non-stationary variables
use "Merged_data.dta", clear
gen double date_num = date(date, "YMD")
format date_num %td
drop date
rename date_num date
tsset date

//Original sequence ADF test
dfuller YFK, lags(2) regress
dfuller exchange_rate, lags(2) regress
dfuller tbill_rate, lags(2) regress


//Generate a first-order difference
gen d_YFK = d.YFK
gen d_exchange_rate = d.exchange_rate
gen d_tbill_rate = d.tbill_rate

//Then check whether the difference is stable
dfuller d_YFK, lags(2) regress
dfuller d_exchange_rate, lags(2) regress
dfuller d_tbill_rate, lags(2) regress

//Missing date interpolation fill (if there are missing dates in the data)
preserve
clear

//Assume 2010.01.04 to the end of 2020, a total 4015 days
set obs 4015
gen date = td(04jan2010) + _n - 1
format date %td
save "full_dates.dta", replace
restore

use "Merged_data.dta", clear
rename date date_orig
gen date = date(date_orig, "YMD")
format date %td
drop date_orig
save "Merged_data.dta", replace

use "full_dates.dta", clear
merge 1:1 date using "Merged_data.dta"
drop _merge

//Interpolate against key variables
foreach var of varlist exchange_rate YFK tbill_rate {
    ipolate `var' date, gen(`var'_filled)
    drop `var'
    rename `var'_filled `var'
}

//Forward and backward filling
foreach var of varlist exchange_rate YFK tbill_rate {
    by date: replace `var' = `var'[_n-1] if missing(`var')
    by date: replace `var' = `var'[_n+1] if missing(`var')
}

tsset date
save "filled_data_final.dta", replace


//Read and set the data
use "filled_data_final.dta", clear
tsset date
//Select the optimal lag order
varsoc exchange_rate YFK tbill_rate, maxlag(12)
//Three-variable Johansen cointegration test
vecrank exchange_rate YFK tbill_rate, lags(8) trend(constant)
//the best lag is 8
//If rank=1, estimate the three-variable VECM
vec exchange_rate YFK tbill_rate, lags(8)

//stable test
vecstable 

//Extract cointegration residuals
predict cointres_3vars, residuals
tsline cointres_3vars, title("3 variable VECM cointegration residue")
graph export "cointegration residuals.png", replace
summarize cointres_3vars
dfuller cointres_3vars, lags(8) regress
list date cointres_3vars in 1/10

//impulse response function
irf create My3varModel, step(10) set(my3var_irf) replace

//impact of exchange rate shocks on HSI
irf graph irf, impulse(exchange_rate) response(YFK) ///
    title("Impulse: Exchange_rate -> HSI")
graph export "mpulse: Exchange_rate.png", replace

//impact of TBill shocks on HSI
irf graph irf, impulse(tbill_rate) response(YFK) ///
    title("Impulse: TBill_rate -> HSI")
graph export "Impulse: TBill_rate -> HSI.png", replace



