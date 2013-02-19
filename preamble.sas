%let base_dir = /home/mpg1/projects/accounting_returns;
%PUT &base_dir;%PUT ;
%let data_dir = &base_dir/data;
%PUT &data_dir;%PUT ;
%let code_dir = &base_dir/accounting-predictability;
%PUT &code_dir;%PUT ;
libname USER "&data_dir";
%INCLUDE "&base_dir/MACROS.SAS";
