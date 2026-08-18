#!/usr/bin/env bash
# cache — prompt-cache hit ratio for the latest response.
#
#   hit = cache_read / (input + cache_creation + cache_read)
#
# A low ratio right after a cache write is normal, so this is a health hint
# rather than an alarm. The number is always printed, so color is never the
# only signal (docs/CODING-STANDARDS.md §8).
segment_cache() {
  local read_t create_t input_t total hit color
  read_t=$(sl_int cache_read 0)
  create_t=$(sl_int cache_create 0)
  input_t=$(sl_int usage_input 0)
  total=$((read_t + create_t + input_t))
  [ "$total" -gt 0 ] || return 1
  hit=$((read_t * 100 / total))
  color=$(sl_threshold_color "$hit" 50 80 red yellow green)
  sl_paint dim 'cache '
  sl_paint "$color" "${hit}%"
}
