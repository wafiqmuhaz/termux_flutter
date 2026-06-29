cmake_minimum_required(VERSION 3.10.2)
project(termux_flutter_pty C)

add_library(termux_flutter_pty SHARED pty_bridge.c)
find_library(log-lib log)
target_link_libraries(termux_flutter_pty ${log-lib})
