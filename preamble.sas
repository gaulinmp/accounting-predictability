%let base_dir = /home/mpg1/projects/accounting_returns;
%let data_dir = &base_dir/data;
%let code_dir = &base_dir/accounting-predictability;
libname USER "&data_dir";
%INCLUDE "&base_dir/MACROS.SAS";
