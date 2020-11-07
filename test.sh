#!/bin/bash

for i in {1..31}
do
	cp ./Tests/test$i.vmem vmem0.vmem
	iverilog shellproc.v
	(./a.out | tail -1) > ./Output/output$i.txt
	echo Test $i
	diff ./Output/output$i.txt ./Tests/resulttest$i.vmem
done
echo hello world
