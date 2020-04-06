#!/bin/bash

inputfile=$1
while IFS= read -r line
do
  echo -n "$line\n"
done < $inputfile
