# kubernetes-benchmark
Kubernetes benchmark - CPU, Memory, I/O and Network.<br>

<p> Plain script to run a few benchmarks...</p>

Create the namespace iperf before running the script.

## Usage
`run-tests.sh  -cn <host1> -sn <host2> -n iperf`

Use `kubectl logs iperf-client` to see the output. 

Inspired by knb...
