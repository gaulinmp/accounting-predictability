%let base_dir = C:\Users\mpg1\Dropbox\Documents\School;
%PUT &base_dir;%PUT ;
%let data_dir = D:\SAS\return_predictability;
%PUT &data_dir;%PUT ;
%let code_dir = &base_dir\Projects\Return_Predictability_of_Earnings\accounting-predictability;
%PUT &code_dir;%PUT ;
libname USER "&data_dir";
%INCLUDE "&base_dir/MACROS.SAS";
