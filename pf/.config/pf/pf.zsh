# Shell integration for pf: completion and the old pf-<name> aliases.
# Sourced from ~/.zshrc.

_pf() {
	local -a subs names
	subs=(start stop toggle restart status logs show list edit help)
	if ((CURRENT == 2)); then
		_describe 'pf command' subs
	else
		names=(${(f)"$(~/.local/bin/pf list-names 2>/dev/null)"})
		[[ $words[2] == stop ]] && names+=(--all)
		_describe 'forward' names
	fi
}
compdef _pf pf

# pf-prod-db etc. keep working, now detached instead of blocking the tab.
for _pf_name in ${(f)"$(~/.local/bin/pf list-names 2>/dev/null)"}; do
	alias "pf-$_pf_name"="pf start $_pf_name"
done
unset _pf_name
