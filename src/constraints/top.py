# The external clock
ctx.addClock("sys_clk", 27)
# Yosys inserts an input buffer; the video logic uses its output net.
# Constraining only the package input leaves this at nextpnr's 12 MHz default.
ctx.addClock("console_video.sys_clk", 27)
# The processor clock
ctx.addClock("clk", 96)
ctx.addClock("console_video.serial_clk", 135)
