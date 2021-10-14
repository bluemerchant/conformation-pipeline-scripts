#!/bin/bash

mkdir ./pdb_sources
while IFS=';' read -r url filename box_size
do
cd ./pdb_sources
mkdir $filename
cd $filename
wget -O "csdb_linear_$box_size.pdb" $url
cd ..
done < dataset.csv
