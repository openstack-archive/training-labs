# The functions in this library are used to get scancode strings for virsh
# keyboard input (send-key).
#
# It is based on:
# http://libvirt.org/git/?p=libvirt.git;a=blob_plain;f=src/util/keymaps.csv
#
# The library works with bash 3.2 (shipped with Mac OS X as of 2014).

function char2scancode {
    local key=$1
    case "$key" in
        'a')
            echo -n " KEY_A"
            ;;
        'b')
            echo -n " KEY_B"
            ;;
        'c')
            echo -n " KEY_C"
            ;;
        'd')
            echo -n " KEY_D"
            ;;
        'e')
            echo -n " KEY_E"
            ;;
        'f')
            echo -n " KEY_F"
            ;;
        'g')
            echo -n " KEY_G"
            ;;
        'h')
            echo -n " KEY_H"
            ;;
        'i')
            echo -n " KEY_I"
            ;;
        'j')
            echo -n " KEY_J"
            ;;
        'k')
            echo -n " KEY_K"
            ;;
        'l')
            echo -n " KEY_L"
            ;;
        'm')
            echo -n " KEY_M"
            ;;
        'n')
            echo -n " KEY_N"
            ;;
        'o')
            echo -n " KEY_O"
            ;;
        'p')
            echo -n " KEY_P"
            ;;
        'q')
            echo -n " KEY_Q"
            ;;
        'r')
            echo -n " KEY_R"
            ;;
        's')
            echo -n " KEY_S"
            ;;
        't')
            echo -n " KEY_T"
            ;;
        'u')
            echo -n " KEY_U"
            ;;
        'v')
            echo -n " KEY_V"
            ;;
        'w')
            echo -n " KEY_W"
            ;;
        'x')
            echo -n " KEY_X"
            ;;
        'y')
            echo -n " KEY_Y"
            ;;
        'z')
            echo -n " KEY_Z"
            ;;
        'A')
            echo -n " KEY_LEFTSHIFT KEY_A"
            ;;
        'B')
            echo -n " KEY_LEFTSHIFT KEY_B"
            ;;
        'C')
            echo -n " KEY_LEFTSHIFT KEY_C"
            ;;
        'D')
            echo -n " KEY_LEFTSHIFT KEY_D"
            ;;
        'E')
            echo -n " KEY_LEFTSHIFT KEY_E"
            ;;
        'F')
            echo -n " KEY_LEFTSHIFT KEY_F"
            ;;
        'G')
            echo -n " KEY_LEFTSHIFT KEY_G"
            ;;
        'H')
            echo -n " KEY_LEFTSHIFT KEY_H"
            ;;
        'I')
            echo -n " KEY_LEFTSHIFT KEY_I"
            ;;
        'J')
            echo -n " KEY_LEFTSHIFT KEY_J"
            ;;
        'K')
            echo -n " KEY_LEFTSHIFT KEY_K"
            ;;
        'L')
            echo -n " KEY_LEFTSHIFT KEY_L"
            ;;
        'M')
            echo -n " KEY_LEFTSHIFT KEY_M"
            ;;
        'N')
            echo -n " KEY_LEFTSHIFT KEY_N"
            ;;
        'O')
            echo -n " KEY_LEFTSHIFT KEY_O"
            ;;
        'P')
            echo -n " KEY_LEFTSHIFT KEY_P"
            ;;
        'Q')
            echo -n " KEY_LEFTSHIFT KEY_Q"
            ;;
        'R')
            echo -n " KEY_LEFTSHIFT KEY_R"
            ;;
        'S')
            echo -n " KEY_LEFTSHIFT KEY_S"
            ;;
        'T')
            echo -n " KEY_LEFTSHIFT KEY_T"
            ;;
        'U')
            echo -n " KEY_LEFTSHIFT KEY_U"
            ;;
        'V')
            echo -n " KEY_LEFTSHIFT KEY_V"
            ;;
        'W')
            echo -n " KEY_LEFTSHIFT KEY_W"
            ;;
        'X')
            echo -n " KEY_LEFTSHIFT KEY_X"
            ;;
        'Y')
            echo -n " KEY_LEFTSHIFT KEY_Y"
            ;;
        'Z')
            echo -n " KEY_LEFTSHIFT KEY_Z"
            ;;
        '1')
            echo -n " KEY_1"
            ;;
        '2')
            echo -n " KEY_2"
            ;;
        '3')
            echo -n " KEY_3"
            ;;
        '4')
            echo -n " KEY_4"
            ;;
        '5')
            echo -n " KEY_5"
            ;;
        '6')
            echo -n " KEY_6"
            ;;
        '7')
            echo -n " KEY_7"
            ;;
        '8')
            echo -n " KEY_8"
            ;;
        '9')
            echo -n " KEY_9"
            ;;
        '0')
            echo -n " KEY_0"
            ;;
        '!')
            echo -n " KEY_LEFTSHIFT KEY_1"
            ;;
        '@')
            echo -n " KEY_LEFTSHIFT KEY_2"
            ;;
        '#')
            echo -n " KEY_LEFTSHIFT KEY_3"
            ;;
        '$')
            echo -n " KEY_LEFTSHIFT KEY_4"
            ;;
        '%')
            echo -n " KEY_LEFTSHIFT KEY_5"
            ;;
        '^')
            echo -n " KEY_LEFTSHIFT KEY_6"
            ;;
        '&')
            echo -n " KEY_LEFTSHIFT KEY_7"
            ;;
        '*')
            echo -n " KEY_LEFTSHIFT KEY_8"
            ;;
        '(')
            echo -n " KEY_LEFTSHIFT KEY_9"
            ;;
        ')')
            echo -n " KEY_LEFTSHIFT KEY_0"
            ;;
        '-')
            echo -n " KEY_MINUS"
            ;;
        '_')
            echo -n " KEY_LEFTSHIFT KEY_MINUS"
            ;;
        '=')
            echo -n " KEY_EQUAL"
            ;;
        '+')
            echo -n " KEY_LEFTSHIFT KEY_EQUAL"
            ;;
        ' ')
            echo -n " KEY_SPACE"
            ;;
        '[')
            echo -n " KEY_LEFTBRACE"
            ;;
        ']')
            echo -n " KEY_RIGHTBRACE"
            ;;
        '{')
            echo -n " KEY_LEFTSHIFT KEY_LEFTBRACE"
            ;;
        '}')
            echo -n " KEY_LEFTSHIFT KEY_RIGHTBRACE"
            ;;
        ';')
            echo -n " KEY_SEMICOLON"
            ;;
        ':')
            echo -n " KEY_LEFTSHIFT KEY_SEMICOLON"
            ;;
        ',')
            echo -n " KEY_COMMA"
            ;;
        '.')
            echo -n " KEY_DOT"
            ;;
        '/')
            echo -n " KEY_SLASH"
            ;;
        '\')
            echo -n " KEY_BACKSLASH"
            ;;
        '|')
            echo -n " KEY_LEFTSHIFT KEY_BACKSLASH"
            ;;
        '?')
            echo -n " KEY_LEFTSHIFT KEY_SLASH"
            ;;
        '"')
            echo -n " KEY_LEFTSHIFT KEY_APOSTROPHE"
            ;;
        "'")
            echo -n " KEY_APOSTROPHE"
            ;;
        ">")
            echo -n " KEY_LEFTSHIFT KEY_DOT"
            ;;
        "<")
            echo -n " KEY_LEFTSHIFT KEY_COMMA"
            ;;
    esac
}

function esc2scancode {
    echo -n " KEY_ESC"
}

function enter2scancode {
    echo -n " KEY_ENTER"
}

function backspace2scancode {
    echo -n " KEY_BACKSPACE"
}

function f6_2scancode {
    echo -n " KEY_F6"
}

# vim: set ai ts=4 sw=4 et ft=sh:
