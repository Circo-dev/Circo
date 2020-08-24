module LoggerConfig

using Logging

io = open("circo.out", "w")
logger = SimpleLogger(io)
global_logger(logger)

end