#!/usr/bin/env python

# The functions in this library are used to get scancode strings for VirtualBox
# keyboard input (keyboardputscancode).
#
# It was generated mostly from output of Cameron Kerr's scancodes.l:
# http://humbledown.org/keyboard-scancodes.xhtml

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import stacktrain.virtualbox.vm_create as vm


def char2scancode(key):
    keycodes = {
        'a': "1e 9e",
        'b': "30 b0",
        'c': "2e ae",
        'd': "20 a0",
        'e': "12 92",
        'f': "21 a1",
        'g': "22 a2",
        'h': "23 a3",
        'i': "17 97",
        'j': "24 a4",
        'k': "25 a5",
        'l': "26 a6",
        'm': "32 b2",
        'n': "31 b1",
        'o': "18 98",
        'p': "19 99",
        'q': "10 90",
        'r': "13 93",
        's': "1f 9f",
        't': "14 94",
        'u': "16 96",
        'v': "2f af",
        'w': "11 91",
        'x': "2d ad",
        'y': "15 95",
        'z': "2c ac",
        'A': "2a 1e 9e aa",
        'B': "2a 30 b0 aa",
        'C': "2a 2e ae aa",
        'D': "2a 20 a0 aa",
        'E': "2a 12 92 aa",
        'F': "2a 21 a1 aa",
        'G': "2a 22 a2 aa",
        'H': "2a 23 a3 aa",
        'I': "2a 17 97 aa",
        'J': "2a 24 a4 aa",
        'K': "2a 25 a5 aa",
        'L': "2a 26 a6 aa",
        'M': "2a 32 b2 aa",
        'N': "2a 31 b1 aa",
        'O': "2a 18 98 aa",
        'P': "2a 19 99 aa",
        'Q': "2a 10 90 aa",
        'R': "2a 13 93 aa",
        'S': "2a 1f 9f aa",
        'T': "2a 14 94 aa",
        'U': "2a 16 96 aa",
        'V': "2a 2f af aa",
        'W': "2a 11 91 aa",
        'X': "2a 2d ad aa",
        'Y': "2a 15 95 aa",
        'Z': "2a 2c ac aa",
        '1': "02 82",
        '2': "03 83",
        '3': "04 84",
        '4': "05 85",
        '5': "06 86",
        '6': "07 87",
        '7': "08 88",
        '8': "09 89",
        '9': "0a 8a",
        '0': "0b 8b",
        '!': "2a 02 82 aa",
        '@': "2a 03 83 aa",
        '#': "2a 04 84 aa",
        '$': "2a 05 85 aa",
        '%': "2a 06 86 aa",
        '^': "2a 07 87 aa",
        '&': "2a 08 88 aa",
        '*': "2a 09 89 aa",
        '(': "2a 0a 8a aa",
        ')': "2a 0b 8b aa",
        '-': "0c 8c",
        '_': "2a 0c 8c aa",
        '=': "0d 8d",
        '+': "2a 0d 8d aa",
        ' ': "39 b9",
        '[': "1a 9a",
        ']': "1b 9b",
        '{': "2a 1a 9a aa",
        '}': "2a 1b 9b aa",
        ';': "27 a7",
        ':': "2a 27 a7 aa",
        ',': "33 b3",
        '.': "34 b4",
        '/': "35 b5",
        '\\': "2b ab",
        '|': "2a 2b ab aa",
        '?': "2a 35 b5 aa",
        '"': "2a 28 a8 aa",
        "'": "28 a8",
        ">": "2a 34 b4 aa",
        "<": "2a 33 b3 aa"
    }

    return keycodes[key]


def esc2scancode():
    return "01 81"


def enter2scancode():
    return "1c 9c"


def backspace2scancode():
    return "0e 8e"


def f6_2scancode():
    return "40 c0"


def keyboard_push_scancode(vm_name, code_string):
    code = code_string.split(' ')
    vm.vbm("controlvm", vm_name, "keyboardputscancode", *code)
