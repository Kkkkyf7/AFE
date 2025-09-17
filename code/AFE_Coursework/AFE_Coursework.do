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

// Descriptive statistics
summarize YFK exchange_rate tbill_rate

// Unit Root Test (ADF)
dfuller exchange_rate, lags(1) regress
dfuller YFK, lags(1) regress
dfuller tbill_rate, lags(1) regress

// First difference for non-stationary data
gen d_exchange_rate = d.exchange_rate
gen d_YFK = d.YFK
gen d_tbill_rate = d.tbill_rate
drop if d_exchange_rate == . | d_YFK == . | d_tbill_rate == .
dfuller d_exchange_rate, lags(2) regress
dfuller d_YFK, lags(2) regress
dfuller d_tbill_rate, lags(2) regress

// VAR model estimation
var d_exchange_rate d_YFK d_tbill_rate, lags(1/2)

// Granger Causality Test
vargranger

// Impulse response functions
irf create var1, set(var1) step(20) replace
irf graph irf, impulse(d_exchange_rate) response(d_YFK) title("Impulse Response of HSI to Exchange Rate")
graph export "Impulse_Response_HSI_to_Exchange_Rate.png", replace

irf graph irf, impulse(d_YFK) response(d_exchange_rate) title("Impulse Response of Exchange Rate to HSI")
graph export "Impulse_Response_Exchange_Rate_to_HSI.png", replace

irf graph irf, impulse(d_tbill_rate) response(d_YFK) title("Impulse Response of HSI to US 3-Month T-Bill Rate")
graph export "Impulse_Response_HSI_to_TBill_Rate.png", replace


// GARCH model for volatility analysis
//To the HSI
arch d_YFK, arch(1) garch(1)
predict cond_var, variance

tsline cond_var, title("Conditional Variance of HSI") xtitle("Date") ytitle("Conditional Variance")
graph export "Conditional_Variance_HSI.png", replace


// Apply the GARCH(1,1) model to the HKD/USD exchange rate
arch d_exchange_rate, arch(1) garch(1)
predict cond_var_HKD, variance
tsline cond_var_HKD, title("Conditional Variance of HKD/USD Exchange Rate") xtitle("Date") ytitle("Conditional Variance")
graph export "Conditional_Variance_HKD_USD.png", replace

// Apply the GARCH(1,1) model to the Tbill Rate
arch d_tbill_rate, arch(1) garch(1)
predict cond_var_TBill, variance
tsline cond_var_TBill, title("Conditional Variance of T-Bill Rate") xtitle("Date") ytitle("Conditional Variance")
graph export "Conditional_Variance_TBill.png", replace


// Fill missing dates for VECM
preserve
clear
set obs 4015 // Number of days from 2010 to 2020
gen date = td(04jan2010) + _n - 1
format date %td
save full_dates.dta, replace
restore

use Merged_data.dta, clear
gen date_num = date(date, "YMD")
format date_num %td
drop date
rename date_num date
save Merged_data.dta, replace

use full_dates.dta, clear
merge 1:1 date using Merged_data.dta
sort date
replace exchange_rate = . if _merge == 2
replace YFK = . if _merge == 2
replace tbill_rate= . if _merge == 2
drop _merge
save Merged_data_filled.dta, replace

// Fill missing values using interpolation and forward/backward fill
use Merged_data_filled.dta, clear
foreach var of varlist exchange_rate YFK tbill_rate{
    ipolate `var' date, gen(`var'_filled)
    drop `var'
    rename `var'_filled `var'
}

foreach var of varlist exchange_rate YFK tbill_rate{
    bys date: replace `var' = `var'[_n-1] if missing(`var')
}

foreach var of varlist exchange_rate YFK tbill_rate{
    bys date: replace `var' = `var'[_n+1] if missing(`var')
}
tsset date
save "filled_data_final.dta", replace

// Cointegration test with VECM
vecrank exchange_rate YFK, lags(2) trend(constant)
vec exchange_rate YFK, lags(2)

// Plot cointegration residuals
predict coint_res, residuals
tsline coint_res, title("Cointegration Residuals: Exchange Rate and HSI") xtitle("Date") ytitle("Residuals")
graph export "Cointegration_Residuals_Exchange_Rate_HSI.png", replace

// Export results
outreg2 using results.doc, replace word

// Cointegration test for HSI and T-Bill rate
vecrank YFK tbill_rate, lags(2) trend(constant)
// Estimate VECM model
vec YFK tbill_rate, lags(2)
// Plot cointegration residuals
drop coint_res
// Generate cointegration residuals
predict coint_res, residuals
tsline coint_res, title("Cointegration Residuals: HSI and US 3-Month T-Bill Rate") xtitle("Date") ytitle("Residuals")
graph export "Cointegration_Residuals_HSI_TBill_Rate.png", replace
