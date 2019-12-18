# ╭─────────────╥─────────────────────╮
# │ Author:     ║ File:               │
# │ Andrey Orst ║ kaktree.kak         │
# ╞═════════════╩═════════════════════╡
# │ Filetree browser for Kakoune      │
# ╞═══════════════════════════════════╡
# │ GitHub.com/andreyorst/kaktree.kak │
# ╰───────────────────────────────────╯

declare-option -hidden str kaktree__source %sh{printf "%s" "${kak_source%/rc/*}"}
declare-option -hidden str kaktree__perl "require qw(%opt{kaktree__source}/perl/kaktree.pl);"

define-command -docstring "kaktree-enable: Create kaktree window if not exist and enable related hooks." \
kaktree-enable %{
    require-module kaktree
    kaktree-enable-impl
}

provide-module kaktree %§

# Main configuration options
declare-option -docstring "name of the client that kaktree will use to display itself." \
str kaktreeclient 'kaktreeclient'

declare-option -docstring "Choose how to split current pane to display kaktree panel.
    Possible values: vertical, horizontal
    Default value: horizontal" \
str kaktree_split "horizontal"

declare-option -docstring "Choose where to display kaktree panel.
    Possible values: left, right
    Default value: left
When kaktree_split is set to 'horizontal', 'left' and 'right' will make split above or below current pane respectively." \
str kaktree_side "left"

declare-option -docstring "The size of kaktree pane. Can be either a number of columns or size in percentage." \
str kaktree_size '28'

declare-option -docstring "Icon of the closed directory displayed next to direname." \
str kaktree_dir_icon_close '+'

declare-option -docstring "Icon of the opened directory displayed next to direname." \
str kaktree_dir_icon_open '-'

declare-option -docstring "Icon of the file displayed next to filename." \
str kaktree_file_icon '#'

declare-option -docstring "Show hidden files." \
bool kaktree_show_hidden true

declare-option -docstring "Highlight current line in kaktree buffer." \
bool kaktree_hlline true

declare-option -docstring "Sort items in kaktree buffer." \
bool kaktree_sort true

declare-option -docstring "Amount of indentation for nested items. Must be greater than zero." \
int kaktree_indentation 2

declare-option -docstring "Double click interval." \
str kaktree_double_click_duration '0.3'

declare-option -hidden str kaktree__current_click ''

# Helper options
declare-option -hidden str kaktree__jumpclient
declare-option -hidden str kaktree__active 'false'
declare-option -hidden str kaktree__onscreen 'false'
declare-option -hidden str kaktree__current_indent ''
declare-option -hidden str-list kaktree__expanded_paths ''

set-face global kaktree_icon_face default,default+b@comment
set-face global kaktree_hlline_face default,default+@SecondarySelection

add-highlighter shared/kaktree group
add-highlighter shared/kaktree/icon regex ^\h*(.) 1:kaktree_icon_face
add-highlighter shared/kaktree/empty regex ^\h+<empty> 0:comment

hook -group kaktree-syntax global WinSetOption filetype=kaktree %{
    add-highlighter window/kaktree ref kaktree
    hook -always -once window WinSetOption filetype=.* %{
        remove-highlighter window/kaktree
    }
}

define-command -hidden kaktree-hlline-update %{
    try %{ remove-highlighter buffer/hlline }
    try %{ add-highlighter buffer/hlline line %val{cursor_line} kaktree_hlline_face }
}


define-command -hidden kaktree-hlline-toggle %{ try %{ evaluate-commands -buffer *kaktree* %sh{
    if [ "$kak_opt_kaktree_hlline" = "true" ]; then
        printf "%s\n" "hook -group kaktree-hlline buffer RawKey '[jk]|<up>|<down>' kaktree-hlline-update
                       hook -group kaktree-hlline buffer NormalIdle .* kaktree-hlline-update"
    else
        printf "%s\n" "remove-hooks buffer kaktree-hlline
                       remove-highlighter buffer/hlline"
    fi
}}}

hook global WinSetOption kaktree_hlline=.+ kaktree-hlline-toggle

define-command -hidden kaktree-hidden-toggle %{ evaluate-commands %sh{
    if [ "$kak_opt_kaktree_show_hidden" = "true" ]; then
        printf "%s\n" "set-option global kaktree_show_hidden false"
    else
        printf "%s\n" "set-option global kaktree_show_hidden true"
    fi
}}

hook global GlobalSetOption kaktree_show_hidden=.+ kaktree-refresh

define-command -hidden kaktree-enable-impl %{
    evaluate-commands %sh{
        [ "${kak_opt_kaktree__active}" = "true" ] && exit
        printf "%s\n" "set-option global kaktree__jumpclient '${kak_client:-client0}'
                       set-option global kaktree__active true
                       hook -group kaktree-watchers global FocusIn (?!${kak_opt_kaktreeclient}).* %{
                           set-option global kaktree__jumpclient %{${kak_client:-client0}}
                       }"
    }
}

define-command -docstring "kaktree-disable: Disable kaktree, delete kaktreeclient and remove kaktree related hooks" \
kaktree-disable %{
    set-option global kaktree__active 'false'
    set-option global kaktree__onscreen 'false'
    remove-hooks global kaktree-watchers
    try %{ delete-buffer! *kaktree* } catch %{ echo -debug "Can't delete *kaktree* buffer. Error message: %val{error}" }
    try %{ evaluate-commands -client %opt{kaktreeclient} quit } catch %{ echo -debug "Can't close %opt{kaktreeclient}. Error message: %val{error}" }
}

define-command -docstring "kaktree-toggle: Toggle kaktree window on and off" \
kaktree-toggle %{ evaluate-commands %sh{
    if [ "${kak_opt_kaktree__active}" = "true" ]; then
        if [ "${kak_opt_kaktree__onscreen}" = "true" ]; then
            printf "%s\n" "evaluate-commands -client %opt{kaktreeclient} quit
                           set-option global kaktree__onscreen false"
        else
            printf "%s\n" "evaluate-commands kaktree-display
                           set-option global kaktree__onscreen true"
        fi
    fi
}}

define-command -hidden kaktree-display %{ nop %sh{
    [ "${kak_opt_kaktree__onscreen}" = "true" ] && exit

    kaktree_cmd="try %{
                     buffer *kaktree*
                     rename-client %opt{kaktreeclient}
                 } catch %{
                     edit! -debug -scratch *kaktree*
                     set-option buffer filetype kaktree
                     rename-client %opt{kaktreeclient}
                     kaktree-refresh
                 }"

    if [ -n "$TMUX" ]; then
        [ "${kak_opt_kaktree_split}" = "vertical" ] && split="-v" || split="-h"
        [ "${kak_opt_kaktree_side}" = "left" ] && side="-b" || side=
        [ -n "${kak_opt_kaktree_size%%*%}" ] && measure="-l" || measure="-p"
        tmux split-window -f ${split} ${side} ${measure} ${kak_opt_kaktree_size%%%*} kak -c ${kak_session} -e "${kaktree_cmd}"
    elif [ -n "${kak_opt_termcmd}" ]; then
        ( ${kak_opt_termcmd} "sh -c 'kak -c ${kak_session} -e \"${kaktree_cmd}\"'" ) > /dev/null 2>&1 < /dev/null &
    fi
}}

define-command -hidden kaktree-refresh %{ evaluate-commands %sh{
    saved_selection="$kak_selections_desc"

    tmp=$(mktemp -d "${TMPDIR:-/tmp}/kakoune-kaktree.XXXXXXXX")
    tree="${tmp}/tree"
    fifo="${tmp}/fifo"
    mkfifo ${fifo}

    printf "%s\n" "hook global -always KakEnd .* %{ nop %sh{ rm -rf ${tmp} }}"

    base_name() {
        filename="$1"
        case "$filename" in
          */*[!/]*)
            trail=${filename##*[!/]}
            filename=${filename%%"$trail"}
            base=${filename##*/} ;;
          *[!/]*)
            trail=${filename##*[!/]}
            base=${filename%%"$trail"} ;;
          *) base="/" ;;
        esac
        printf "%s\n" "${base}"
    }

    # $kak_opt_kaktree_dir_icon_open
    # $kak_opt_kaktree_dir_icon_close
    # $kak_opt_kaktree_file_icon
    # $kak_opt_kaktree_indentation
    # $kak_opt_kaktree__current_indent
    # $kak_quoted_opt_kaktree__expanded_paths
    # $kak_opt_kaktree_show_hidden
    # $kak_opt_kaktree_sort
    kak_opt_kaktree__current_indent=""
    kaktree_root="$(base_name $(pwd))"
    [ "$kak_opt_kaktree_show_hidden" = "true" ] && hidden="-A"
    command perl -e "$kak_opt_kaktree__perl build_tree('$(pwd)', '$kaktree_root');" > ${tree}

    printf "%s\n" "evaluate-commands -client %opt{kaktreeclient} %{ try %{
                       edit! -debug -fifo ${fifo} *kaktree*
                       map buffer normal '<ret>' ': kaktree-ret-action<ret>'
                       map buffer normal '<tab>' ': kaktree-tab-action<ret>'
                       map buffer normal 'u' ': kaktree-change-root up<ret>'
                       map buffer normal 'H' ': kaktree-hidden-toggle<ret>'
                       map buffer normal 'r' ': kaktree-refresh<ret>'
                       map buffer normal 'd' ': kaktree-file-delete<ret>'
                       map buffer normal 'y' ': kaktree-file-yank<ret>'
                       map buffer normal 'p' ': kaktree-file-paste cp<ret>'
                       map buffer normal 'P' ': kaktree-file-paste mv<ret>'
                       map buffer normal 'L' ': kaktree-file-paste %{ln -s}<ret>'
                       map buffer normal 'R' ': kaktree-file-rename<ret>'
                       hook buffer RawKey '<mouse:press_left:.*>' kaktree-mouse-action
                       set-option buffer tabstop 1
                   }}"

    (
        cat ${tree} > ${fifo}; rm -rf ${tmp};
        # Restore the selections after the tree has been loaded
        printf "%s\n" "evaluate-commands -client %opt{kaktreeclient} %{
            select $saved_selection
        }" | kak -p "$kak_session"
    ) > /dev/null 2>&1 < /dev/null &
}}

define-command -hidden kaktree-ret-action %{ evaluate-commands -save-regs 'a' %{
    try %{
        set-register a %opt{kaktree_dir_icon_close}
        execute-keys -draft '<a-x>s^\h*\Q<c-r>a<ret>'
        kaktree-change-root
    } catch %{
        set-register a %opt{kaktree_dir_icon_open}
        execute-keys -draft '<a-x>s^\h*\Q<c-r>a<ret>'
        kaktree-change-root
    } catch %{
        set-register a %opt{kaktree_file_icon}
        execute-keys -draft '<a-x>s^\h*\Q<c-r>a<ret>'
        kaktree-file-open
    } catch %{
        nop
    }
}}

define-command -hidden kaktree-mouse-action %{ evaluate-commands -save-regs 'c' %{
    execute-keys -draft 'x"cy'
    evaluate-commands %sh{
        if [ "$kak_reg_c" = "$kak_opt_kaktree__current_click" ]; then
            printf "%s\n" "kaktree-click-action"
        else
            printf "%s\n" "kaktree-set-temporarely %reg{c}"
        fi
    }
}}

define-command -hidden kaktree-set-temporarely -params 1 %{ evaluate-commands %sh{ (
    [ -z "${1##*&*}" ] && tmp=$(printf "%s" "$1" | sed "s/&/&&/g") || tmp="$1"
    printf "%s\n" "set-option global kaktree__current_click %&$tmp&" | kak -p $kak_session
    sleep $kak_opt_kaktree_double_click_duration
    printf "%s\n" "set-option global kaktree__current_click ''" | kak -p $kak_session
) >/dev/null 2>&1 </dev/null & }}

define-command -hidden kaktree-click-action %{ evaluate-commands -save-regs 'a' %{
    try %{
        set-register a %opt{kaktree_dir_icon_close}
        execute-keys -draft '<a-x>s^\h*\Q<c-r>a<ret>'
        kaktree-dir-unfold
    } catch %{
        set-register a %opt{kaktree_dir_icon_open}
        execute-keys -draft '<a-x>s^\h*\Q<c-r>a<ret>'
        kaktree-dir-fold
    } catch %{
        set-register a %opt{kaktree_file_icon}
        execute-keys -draft '<a-x>s^\h*\Q<c-r>a<ret>'
        kaktree-file-open
    } catch %{
        nop
    }
}}

define-command -hidden kaktree-tab-action %{ evaluate-commands -save-regs 'a' %{
    try %{
        set-register a %opt{kaktree_dir_icon_close}
        execute-keys -draft '<a-x>s^\h*\Q<c-r>a\E<ret>'
        kaktree-dir-unfold
    } catch %{
        set-register a %opt{kaktree_dir_icon_open}
        execute-keys -draft '<a-x>s^\h*\Q<c-r>a\E<ret>'
        kaktree-dir-fold
    } catch %{
        nop
    }
}}

define-command -hidden kaktree-dir-unfold %{ evaluate-commands -save-regs 'abck"' %{
    kaktree-get-current-path
    evaluate-commands %sh{
        # Perl will need these variables:
        # $kak_opt_kaktree_dir_icon_open
        # $kak_opt_kaktree_dir_icon_close
        # $kak_opt_kaktree_file_icon
        # $kak_opt_kaktree_indentation
        # $kak_opt_kaktree__current_indent
        # $kak_opt_kaktree_show_hidden
        # $kak_quoted_opt_kaktree__expanded_paths
        # $kak_opt_kaktree_sort
        dir_path="$kak_reg_k"
        kaktree_root=$(basename -- "$dir_path")
        tree=$(command perl -e "$kak_opt_kaktree__perl build_tree('$dir_path', '$kaktree_root');")
        printf "%s\n" "set -add global kaktree__expanded_paths '$dir_path'"

        printf "%s\n" "set-register '\"' %{$tree
}"
        printf "%s\n" "execute-keys '<a-x>R'"
        printf "%s\n" "select $kak_selection_desc"
    }
}}

define-command -hidden kaktree-dir-fold %{ evaluate-commands -save-regs 'k"/' %{
    kaktree-get-current-path
    evaluate-commands %sh{
        expanded=$(echo " $kak_quoted_opt_kaktree__expanded_paths " | sed "s| $kak_quoted_reg_k | |g")
        printf "%s\n" "set global kaktree__expanded_paths $expanded"

        # Perform the deletion
        printf "%s\n" "execute-keys 'j<a-i>idkI<space><esc><a-h>;/\Q<space>${kak_opt_kaktree_dir_icon_open}\E<ret>c${kak_opt_kaktree_dir_icon_close}<esc>gh'"
        printf "%s\n" "select $kak_selection_desc"
    }
}}


define-command -hidden  \
-docstring "Open a prompt in the jumpclient to run a shell command, and focus the kaktree client again when done" \
kaktree-shell-prompt -params ..1 %{ evaluate-commands -client %opt{kaktree__jumpclient} %{
    focus %opt{kaktree__jumpclient}
    prompt -init %arg{1} -on-abort %{
        focus %opt{kaktreeclient}
    } "run: " %{
        try %{
            echo %sh{ $kak_text }
        } catch %{
            echo -debug "Error running command %val{text}:"
            echo -debug %val{error}
            echo -markup "{Error}%val{error}"
        }
        focus %opt{kaktreeclient}
        kaktree-refresh
    }
}}

define-command -hidden kaktree-get-current-path -params ..1 -docstring \
"Saves the path at the cursor into the given register, which cant be a, b or c, and defaults to k" \
%{ evaluate-commands -client %opt{kaktreeclient} -save-regs 'abc' %{
    # store current file name into register 'a'
    execute-keys -draft '<a-h><a-l>"ay'

    # store current amount of indentation to the register 'b'
    try %{
        execute-keys -draft '<a-x>s^\h+<ret>"by'
        set-option global kaktree__current_indent %reg{b}
    } catch %{
        set-option global kaktree__current_indent ''
    }

    # store entire tree into register 'c' to build up path to current file
    execute-keys -draft '<a-x><a-h>Gk"cy'

    evaluate-commands %sh{
        # Portable command to get a canonicalized path
        real_path() {
            cd "$(dirname "$1")"
            echo "$(pwd)/$(basename "$1")"
        }
        register=${1:-k}
        # Perl will need these variables:
        # $kak_opt_kaktree_dir_icon_open
        # $kak_opt_kaktree_dir_icon_close
        # $kak_opt_kaktree_file_icon
        # $kak_opt_kaktree_indentation
        # $kak_opt_kaktree__current_indent

        file=$(printf "%s\n" "$kak_reg_a" | perl -pe "s/\s*(\Q$kak_opt_kaktree_file_icon\E|\Q$kak_opt_kaktree_dir_icon_close\E|\Q$kak_opt_kaktree_dir_icon_open\E) (.*)$/\$2/g;")

        # build full path based on indentation to the currently expanded directory.
        current_path=$(printf "%s\n" "$kak_quoted_reg_c" | perl -e "$kak_opt_kaktree__perl make_path();")
        file_path=$(printf "%s\n" "$(pwd)/$current_path/$file" | sed "s/#/##/g")
        file_path=$(real_path "$file_path")
        # If the cursor is at 1, we're at the top level
        [ $kak_cursor_line = 1 ] && file_path="$(pwd)"
        printf "%s\n" "set-register $register %#$file_path#"
    }
}}

define-command -hidden kaktree-file-delete %{ evaluate-commands -save-regs 'k' %{
    kaktree-get-current-path
    kaktree-shell-prompt "rm %val{main_reg_k}"
}}

define-command -hidden kaktree-file-yank %{
    kaktree-get-current-path
    evaluate-commands -client %opt{kaktree__jumpclient} %{
        echo -markup "{Information}Yanked %val{main_reg_k} to register k"
    }
}

# parameter is command to run, i.e. mv, cp or ln -s
define-command -hidden kaktree-file-paste -params 1 %{  evaluate-commands -save-regs 'd' %{
    kaktree-get-current-path d
    kaktree-shell-prompt "%arg{1} %val{main_reg_k} %val{main_reg_d}"
}}

define-command -hidden kaktree-file-rename %{ evaluate-commands -save-regs 'k' %{
    kaktree-get-current-path
    kaktree-shell-prompt "mv %val{main_reg_k} %val{main_reg_k}"
}}

define-command -hidden kaktree-file-open %{ evaluate-commands -client %opt{kaktree__jumpclient} -save-regs 'k"' %{
    kaktree-get-current-path
    focus
    edit -existing "%val{main_reg_k}"
}}

define-command -hidden kaktree-change-root -params ..1 %{ evaluate-commands -save-regs 'ab"' %{
    kaktree-get-current-path
    evaluate-commands %sh{
        base_name=$(basename -- "$kak_reg_k")
        if [ "$kak_reg_k" = "$(pwd)" ] || [ "$1" = "up" ]; then
            printf "%s\n" "change-directory .."
        else
            printf "%s\n" "change-directory %#$kak_reg_k#"
        fi
        printf "%s\n" "kaktree-refresh"
    }
}}

hook global ClientClose .* %{ evaluate-commands -client %opt{kaktreeclient} %sh{
    eval "set -- ${kak_quoted_client_list}"
    if [ $# -eq 1 ] && [ "$1" = "${kak_opt_kaktreeclient}" ]; then
        printf "%s\n" "kaktree-disable"
    fi
}}

§

hook global ModuleLoaded powerline %§

# format modeline in filetree window
# requires `powerline.kak' plugin: https://github.com/andreyorst/powerline.kak
hook -group kaktree-powerline global WinSetOption filetype=kaktree %{
    declare-option str powerline_format
    set-option window powerline_format ""
}

§

# kak: indentwidth=4:tabstop=4
