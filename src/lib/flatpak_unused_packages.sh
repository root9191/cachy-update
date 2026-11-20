#!/bin/bash

# flatpak_unused_packages.sh: Display flatpak unused packages and offer to remove them
# https://github.com/Antiz96/arch-update
# SPDX-License-Identifier: GPL-3.0-or-later

# Unattended mode: directly remove unused packages (flatpak prints what it removes), no listing / question needed
if [ -n "${auto_mode}" ]; then
	# LC_ALL=C to reliably detect the "Nothing unused" case
	flatpak_output=$(LC_ALL=C flatpak uninstall --unused "${flatpak_auto_opt[@]}" 2>&1)
	flatpak_exit_code=$?

	if [ "${flatpak_exit_code}" -ne 0 ]; then
		main_msg "$(eval_gettext "Removing Flatpak Unused Packages...")"
		echo "${flatpak_output}"
		echo
		error_msg "$(eval_gettext "An error has occurred during the removal process\nThe removal has been aborted\n")"
	elif grep -q "Nothing unused to uninstall" <<< "${flatpak_output}"; then
		info_msg "$(eval_gettext "No Flatpak unused package found\n")"
	else
		main_msg "$(eval_gettext "Removing Flatpak Unused Packages...")"
		echo "${flatpak_output}"
		echo
	fi

	return 0
fi

flatpak_unused=$(flatpak uninstall --unused | sed -n '/^ 1./,$p' | awk '{print $2}' | grep -v '^$' | sed '$d')

if [ -n "${flatpak_unused}" ]; then
	main_msg "$(eval_gettext "Flatpak Unused Packages:")"
	echo -e "${flatpak_unused}\n"

	if [ "$(echo "${flatpak_unused}" | wc -l)" -eq 1 ]; then
		ask_msg "$(eval_gettext "Would you like to remove this Flatpak unused package now? [y/N]")" "y"
	else
		ask_msg "$(eval_gettext "Would you like to remove these Flatpak unused packages now? [y/N]")" "y"
	fi

	# shellcheck disable=SC2154
	case "${answer}" in
		"$(eval_gettext "Y")"|"$(eval_gettext "y")")
			echo
			main_msg "$(eval_gettext "Removing Flatpak Unused Packages...")"

			if ! flatpak uninstall --unused "${flatpak_auto_opt[@]}"; then
				echo
				error_msg "$(eval_gettext "An error has occurred during the removal process\nThe removal has been aborted\n")"
			else
				echo
				info_msg "$(eval_gettext "The removal has been applied\n")"
			fi
		;;
		*)
			echo
			info_msg "$(eval_gettext "The removal hasn't been applied\n")"
		;;
	esac
else
	info_msg "$(eval_gettext "No Flatpak unused package found\n")"
fi
