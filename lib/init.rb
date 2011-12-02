# Put local libs that need to be loaded here.
#
$LOAD_PATH.insert(0, './irc')

# The following four libs are REQUIRED!
require "string"
require "kernel"
require "events"
require "plugin"
require "simpleconfig"
require "irc/IRC"

