#!/bin/bash
# is-cmm-ext.sh — Shared extension check for CMM hooks (source, don't execute)
# Provides: is_cmm_ext <file_path>  →  return 0 (match) or 1 (no match)
#
# Built-in extensions and filenames (covering CMM's 155-language grammar set)
# are checked inline (zero overhead).
# User-defined extensions from CMM config are cached per repo root in
# /tmp/cmm-user-ext-<hash>, built lazily on first miss.
#
# Install: cp -r hooks/lib ~/.claude/hooks/
# Hooks source via: source "${BASH_SOURCE[0]%/*}/lib/is-cmm-ext.sh"

is_cmm_ext() {
  local file="$1"
  [ -z "$file" ] && return 1

  # --- Fast path: built-in extensions (covers CMM's 155-language grammar set) ---
  case "$file" in
    *.py|*.go|*.js|*.jsx|*.ts|*.tsx|*.rs|*.java|*.cpp|*.cc|*.ccm|*.cxx|*.cppm|*.c|*.h|*.hh|*.hpp|*.hxx|*.ixx|*.cs|\
    *.php|*.lua|*.scala|*.sc|*.kt|*.kts|*.rb|*.gemspec|*.rake|*.sh|*.bash|*.zsh|*.zig|*.ex|*.exs|*.hs|\
    *.ml|*.mli|*.m|*.mm|*.swift|*.dart|*.pl|*.pm|*.groovy|*.gradle|*.erl|*.hrl|*.r|*.R|\
    *.clj|*.cljs|*.cljc|*.fs|*.fsx|*.fsi|*.jl|*.vim|*.vimrc|*.nix|*.lisp|*.cl|*.lsp|*.elm|*.el|*.lean|\
    *.f90|*.f95|*.f03|*.f08|*.cu|*.cuh|*.cob|*.cbl|*.v|*.sv|*.svh|*.frm|*.prc|*.wl|*.wls|\
    *.mag|*.magma|*.matlab|*.mlx|*.mk|*.meson|*.dockerfile|\
    *.md|*.mdx|*.html|*.htm|*.css|*.scss|*.sass|*.yaml|*.yml|*.toml|*.hcl|*.tf|*.sql|*.vue|*.svelte|\
    *.graphql|*.gql|*.proto|*.cmake|*.glsl|*.frag|*.vert|*.ini|*.cfg|*.conf|\
    *.json|*.xml|*.xsd|*.xsl|*.svg|\
    *.sol|*.typ|*.gd|*.gleam|*.ps1|*.psm1|*.psd1|*.pas|*.lpr|*.dpr|*.cr|*.d|*.nim|*.nims|*.purs|*.res|*.resi|*.odin|*.pony|\
    *.move|*.cairo|*.tcl|*.fish|*.awk|*.s|*.S|*.nasm|*.smali|\
    *.adb|*.ads|*.agda|*.astro|*.fnl|*.janet|*.rkt|*.scm|*.ss|*.luau|*.tl|\
    *.bib|*.rst|*.po|*.pot|*.diff|*.patch|*.csv|*.json5|*.kdl|*.ron|*.pkl|*.ncl|*.jsonnet|*.libsonnet|\
    *.bb|*.bbappend|*.bbclass|*.bzl|*.gn|*.gni|*.star|*.tla|*.thrift|*.smithy|*.capnp|*.prisma|*.properties|\
    *.dts|*.dtsi|*.overlay|*.ld|*.lds|*.fc|*.ll|*.td|*.beancount|\
    *.fx|*.hl|*.hlsl|*.hlsli|*.ispc|*.slang|*.wgsl|\
    *.bicep|*.gotmpl|*.j2|*.jinja|*.jinja2|*.liquid|*.tmpl|*.templ|*.mermaid|*.mmd|\
    *.blade.php|*.sw|*.ha|*.nut|*.cls|*.soql|*.sosl|*.trigger|*.wit|*.vhd|*.vhdl|*.env)
      return 0 ;;
  esac

  # --- Fast path: known filenames (no extension or special build files) ---
  local _basename
  _basename=$(basename "$file")
  case "$_basename" in
    Dockerfile|.dockerignore|.gitignore|.gitattributes|.npmignore|\
    .env|.env.local|.env.development|.env.production|\
    .zshrc|.zshenv|.zprofile|\
    BUILD|BUILD.bazel|WORKSPACE|WORKSPACE.bazel|\
    Justfile|justfile|.justfile|\
    Kconfig|go.mod|\
    hyprland.conf|ssh_config|sshd_config|\
    requirements.txt|requirements-dev.txt|requirements-test.txt)
      return 0 ;;
  esac

  # --- Slow path: user-defined extensions (cached per repo root) ---
  local repo_root
  repo_root=$(cd "$(dirname "$file")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
  [ -z "$repo_root" ] && return 1

  local cache_key cache_file
  cache_key=$(echo -n "$repo_root" | md5 2>/dev/null || echo -n "$repo_root" | md5sum 2>/dev/null | cut -d' ' -f1)
  cache_file="/tmp/cmm-user-ext-${cache_key}"

  # Build cache if missing (once per session/repo)
  if [ ! -f "$cache_file" ]; then
    local global_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/codebase-memory-mcp/config.json"
    local project_cfg="${repo_root}/.codebase-memory.json"

    python3 -c "
import json, os
exts = {}
for path in ['$global_cfg', '$project_cfg']:
    if os.path.isfile(path):
        try:
            with open(path) as f:
                cfg = json.load(f)
            for ext in cfg.get('extra_extensions', {}):
                exts[ext] = True
        except (json.JSONDecodeError, IOError):
            pass
for ext in sorted(exts):
    print(ext)
" 2>/dev/null > "$cache_file" || { rm -f "$cache_file"; return 1; }
  fi

  # Empty cache = no user extensions
  [ ! -s "$cache_file" ] && return 1

  # Check file against cached user extensions (handles compound like .blade.php)
  local basename ext
  basename=$(basename "$file")
  while IFS= read -r ext; do
    case "$basename" in
      *"$ext") return 0 ;;
    esac
  done < "$cache_file"

  return 1
}
