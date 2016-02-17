#!/bin/bash
# vim:set ts=4 tw=80 sw=4 et cindent si
#/**********************************************************************
#    pwsafe2pass
#    Copyright (C) 2015 DaTaPaX (Todd Harbour t/a)
#
#    This program is free software; you can redistribute it and/or
#    modify it under the terms of the GNU General Public License
#    version 3 ONLY, as published by the Free Software Foundation.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program, in the file COPYING or COPYING.txt; if
#    not, see http://www.gnu.org/licenses/ , or write to:
#      The Free Software Foundation, Inc.,
#      51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
# **********************************************************************/

cur_load='\033[u\033[K'
cur_save='\033[s'

binname="$(basename "${0}")"

# Substitution character for '/' in groups
slrp_grp="+"

function show_help() {

cat <<EOF
Usage: ${binname} [--help|-h]
       ${binname} <pwfile>

Parses the text export of your pwsafe password safe database and imports it into
pass.

    --help|-h   Show this help
    <pwfile>    The pwsafe export file, generated with: pwsafe --exportdb

Example:
    ${binname} my_export.txt
EOF

}

[ ${#} -ne 1 ] || [ "${1}" == "--help" ] || [ "${1}" == "-h" ] && {
    show_help
    exit 128
}

[ ! -r "${1}" ] && {
    echo "ERROR: Failed to read pwsafe export file $1" >&2
    exit 129
}

#IFS="	" # tab character
IFS=$'\t'

skipheader=0

count_in=0
count_out=0
while read -r uuid group name login pass notes; do #{
    [ ${skipheader} -eq 0 ] && {
        [ "${uuid}" != "# passwordsafe version 2.0 database" ] && {
            echo "ERROR: File $1 does not appear to be a valid"\
            " passwordsafe database export" >&2
            exit 130
        }

        skipheader=1
        continue
    }

    [ ${skipheader} -eq 1 ] && {
        [    "${uuid}"  != "uuid"   ]\
        || [ "${group}" != "group"  ]\
        || [ "${name}"  != "name"   ]\
        || [ "${login}" != "login"  ]\
        || [ "${pass}"  != "passwd" ]\
        || [ "${notes}" != "notes"  ]\
        && {
            echo "ERROR: File $1 does not appear to be a valid"\
            " passwordsafe database export" >&2
            exit 131
        }

        skipheader=2
        continue
    }

    # Skip blank or invalid lines
    [    -z "${uuid}" ]\
    || [ -z "${name}" ]\
    && continue

    # Remove doublequotes
    [ "${group:0:1}" == '"' ] && [ "${group: -1:1}" == '"' ] && group="${group:1: -1}"
    [ "${name:0:1}"  == '"' ] && [ "${name: -1:1}"  == '"' ] && name="${name:1: -1}"
    [ "${login:0:1}" == '"' ] && [ "${login: -1:1}" == '"' ] && login="${login:1: -1}"
    [ "${pass:0:1}"  == '"' ] && [ "${pass: -1:1}"  == '"' ] && pass="${pass:1: -1}"
    [ "${notes:0:1}" == '"' ] && [ "${notes: -1:1}" == '"' ] && notes="${notes:1: -1}"

    # Remove '/' from groups
    group="${group//\//${slrp_grp}}"

#TODO: Sanitise name

    # Remove newlines from notes
    notes="${notes//\\012/\\n}"

    # Extract URL(s) from notes
    urls=( $(echo "${notes}"|sed -n '/^http:/p;/^ftp:/p'))
    notes="$(echo "${notes}"|sed    '/^http:/d;/^ftp:/d')"



    #
    # BUILD SUBMIT STRING
    ########################################

    submit=""

    # Password
    submit="${submit}${pass}\n"

    # Login name
    [ ! -z "${login}" ] && submit="${submit}login:${login}\n"

    # URL(s)
    [ ${#urls[@]} -gt 1 ] && {
        for i in $(seq 1 ${#urls[@]}); do #{
            submit="${submit}url${i}:${urls[${i}]}"
        done #}
    } || [ ! -z "${urls}" ] && {
        submit="${submit}url:${urls}"
    }

    # Notes
    [ ! -z "${notes}" ] && submit="${submit}${notes}\n"

    outfile="${name}"
    [ ! -z "${group}" ] && outfile="${group}/${name}"

    count_in=$((${count_in} + 1))

    echo -en "${cur_save}[...] NEW: ${outfile}..."

    #echo -e $entry | pass insert --multiline --force "$name"
    echo -e "${submit}"|pass insert --multiline -- "${outfile}" && {
        count_out=$((${count_out} + 1))

        echo -e "${cur_load}[OK.] NEW: ${outfile}"

    } || {
        echo -e "${cur_load}[ERR] NEW: ${outfile}: ERROR:"
        echo -e "---\n${submit}---\n"

    }

done <"${1}" #}

echo -e "\n*** COMPLETE: Imported ${count_out} of ${count_in}"
