#!/usr/bin/env sh

# Download Sqlite c amalgamation
wget -c -O sqlite.zip \
    https://www.sqlite.org/2025/sqlite-amalgamation-3490100.zip

# Extract 
unzip sqlite.zip
mv -f sqlite-amalgamation*/ sqlite-amalgamation/
mv -f sqlite-amalgamation/sqlite3.c sqlite-amalgamation/sqlite3.h .
rm -r sqlite-amalgamation/
rm -r sqlite.zip
