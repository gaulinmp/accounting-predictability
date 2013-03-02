%let base_dir = D:\Dropbox\Documents\School;
%PUT &base_dir;%PUT ;
%let data_dir = D:\SAS\return_predictability;
%PUT &data_dir;%PUT ;
%let code_dir = &base_dir\Projects\Return_Predictability_of_Earnings\gitrepo;
%PUT &code_dir;%PUT ;
libname USER "&data_dir";
%INCLUDE "&base_dir/MACROS.SAS";
