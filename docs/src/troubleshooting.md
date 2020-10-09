# Troubleshooting

**Circo is in alpha stage. Several stability issues are known. Please file an issue if you cannot find the workaround here!**

#### The frontend fails to display the correct number of schedulers

Open the JavaScript console (F12) and reload the page. You should see exactly one connection error message, and for every scheduler a log about "actor registration". If not, then you may need to restart your browser. It may also be possible that orphaned Circo schedulers are running.

#### Sometimes the backend crashes when the browser disconnects

This seems like a bug in HTTP.jl or in Julia itself, partially workarounded, so happens rarely. Work on fixing this hasn't yet started, the only known workaround at the time is not closing the browser and not reloading the page while connected to the backend. Note that using the monitoring
frontend is optional.

#### The cluster does not handle node removal

Not yet implemented, and no workaround is available, but seems like relatively straightforward to fix.
