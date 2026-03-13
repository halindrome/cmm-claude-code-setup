#!/bin/bash
# Aggregate per-run benchmark CSV rows into mean/stddev statistics grouped by (variant, repo, task)

if [ -z "$1" ]; then
  echo "Usage: $0 <results.csv>" >&2
  exit 1
fi

if [ ! -f "$1" ]; then
  echo "Error: File not found: $1" >&2
  exit 1
fi

awk -F',' '
NR == 1 { next }  # skip header
{
  variant = $1; repo = $2; task = $3
  key = variant SUBSEP repo SUBSEP task

  input = $5+0; output = $6+0; cache_creation = $7+0; cache_read = $8+0; total = $9+0

  count[key]++

  sum_input[key]      += input
  sum_sq_input[key]   += input * input
  sum_output[key]     += output
  sum_sq_output[key]  += output * output
  sum_cc[key]         += cache_creation
  sum_sq_cc[key]      += cache_creation * cache_creation
  sum_cr[key]         += cache_read
  sum_sq_cr[key]      += cache_read * cache_read
  sum_total[key]      += total
  sum_sq_total[key]   += total * total

  # remember group label parts
  label_variant[key] = variant
  label_repo[key]    = repo
  label_task[key]    = task
}
function stddev(sum, sum_sq, n,    mean, variance) {
  if (n < 1) return 0
  mean = sum / n
  variance = (sum_sq / n) - (mean * mean)
  if (variance < 0) variance = 0
  return sqrt(variance)
}
END {
  print "variant,repo,task,n,input_mean,input_stddev,output_mean,output_stddev,cache_creation_mean,cache_creation_stddev,cache_read_mean,cache_read_stddev,total_mean,total_stddev"
  for (key in count) {
    n = count[key]
    printf "%s,%s,%s,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n",
      label_variant[key], label_repo[key], label_task[key], n,
      sum_input[key]/n,      stddev(sum_input[key],     sum_sq_input[key],  n),
      sum_output[key]/n,     stddev(sum_output[key],    sum_sq_output[key], n),
      sum_cc[key]/n,         stddev(sum_cc[key],        sum_sq_cc[key],     n),
      sum_cr[key]/n,         stddev(sum_cr[key],        sum_sq_cr[key],     n),
      sum_total[key]/n,      stddev(sum_total[key],     sum_sq_total[key],  n)
  }
}
' "$1"
