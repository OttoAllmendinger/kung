#!/bin/bash

while true; do
    inotifywait *.tex;
    make;
done
