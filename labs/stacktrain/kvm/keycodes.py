#!/usr/bin/env python

# The functions in this library are used to get scancode strings for virsh
# keyboard input (send-key).
#
# It is based on:
# http://libvirt.org/git/?p=libvirt.git;a=blob_plain;f=src/util/keymaps.csv

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import stacktrain.kvm.vm_create as vm


def char2scancode(key):
    keycodes = {
        'a': "KEY_A",
        'b': "KEY_B",
        'c': "KEY_C",
        'd': "KEY_D",
        'e': "KEY_E",
        'f': "KEY_F",
        'g': "KEY_G",
        'h': "KEY_H",
        'i': "KEY_I",
        'j': "KEY_J",
        'k': "KEY_K",
        'l': "KEY_L",
        'm': "KEY_M",
        'n': "KEY_N",
        'o': "KEY_O",
        'p': "KEY_P",
        'q': "KEY_Q",
        'r': "KEY_R",
        's': "KEY_S",
        't': "KEY_T",
        'u': "KEY_U",
        'v': "KEY_V",
        'w': "KEY_W",
        'x': "KEY_X",
        'y': "KEY_Y",
        'z': "KEY_Z",
        'A': "KEY_LEFTSHIFT KEY_A",
        'B': "KEY_LEFTSHIFT KEY_B",
        'C': "KEY_LEFTSHIFT KEY_C",
        'D': "KEY_LEFTSHIFT KEY_D",
        'E': "KEY_LEFTSHIFT KEY_E",
        'F': "KEY_LEFTSHIFT KEY_F",
        'G': "KEY_LEFTSHIFT KEY_G",
        'H': "KEY_LEFTSHIFT KEY_H",
        'I': "KEY_LEFTSHIFT KEY_I",
        'J': "KEY_LEFTSHIFT KEY_J",
        'K': "KEY_LEFTSHIFT KEY_K",
        'L': "KEY_LEFTSHIFT KEY_L",
        'M': "KEY_LEFTSHIFT KEY_M",
        'N': "KEY_LEFTSHIFT KEY_N",
        'O': "KEY_LEFTSHIFT KEY_O",
        'P': "KEY_LEFTSHIFT KEY_P",
        'Q': "KEY_LEFTSHIFT KEY_Q",
        'R': "KEY_LEFTSHIFT KEY_R",
        'S': "KEY_LEFTSHIFT KEY_S",
        'T': "KEY_LEFTSHIFT KEY_T",
        'U': "KEY_LEFTSHIFT KEY_U",
        'V': "KEY_LEFTSHIFT KEY_V",
        'W': "KEY_LEFTSHIFT KEY_W",
        'X': "KEY_LEFTSHIFT KEY_X",
        'Y': "KEY_LEFTSHIFT KEY_Y",
        'Z': "KEY_LEFTSHIFT KEY_Z",
        '1': "KEY_1",
        '2': "KEY_2",
        '3': "KEY_3",
        '4': "KEY_4",
        '5': "KEY_5",
        '6': "KEY_6",
        '7': "KEY_7",
        '8': "KEY_8",
        '9': "KEY_9",
        '0': "KEY_0",
        '!': "KEY_LEFTSHIFT KEY_1",
        '@': "KEY_LEFTSHIFT KEY_2",
        '#': "KEY_LEFTSHIFT KEY_3",
        '$': "KEY_LEFTSHIFT KEY_4",
        '%': "KEY_LEFTSHIFT KEY_5",
        '^': "KEY_LEFTSHIFT KEY_6",
        '&': "KEY_LEFTSHIFT KEY_7",
        '*': "KEY_LEFTSHIFT KEY_8",
        '(': "KEY_LEFTSHIFT KEY_9",
        ')': "KEY_LEFTSHIFT KEY_0",
        '-': "KEY_MINUS",
        '_': "KEY_LEFTSHIFT KEY_MINUS",
        '=': "KEY_EQUAL",
        '+': "KEY_LEFTSHIFT KEY_EQUAL",
        ' ': "KEY_SPACE",
        '[': "KEY_LEFTBRACE",
        ']': "KEY_RIGHTBRACE",
        '{': "KEY_LEFTSHIFT KEY_LEFTBRACE",
        '}': "KEY_LEFTSHIFT KEY_RIGHTBRACE",
        ';': "KEY_SEMICOLON",
        ':': "KEY_LEFTSHIFT KEY_SEMICOLON",
        ',': "KEY_COMMA",
        '.': "KEY_DOT",
        '/': "KEY_SLASH",
        '\\': "KEY_BACKSLASH",
        '|': "KEY_LEFTSHIFT KEY_BACKSLASH",
        '?': "KEY_LEFTSHIFT KEY_SLASH",
        '"': "KEY_LEFTSHIFT KEY_APOSTROPHE",
        "'": "KEY_APOSTROPHE",
        ">": "KEY_LEFTSHIFT KEY_DOT",
        "<": "KEY_LEFTSHIFT KEY_COMMA"
    }

    return keycodes[key]


def esc2scancode():
    return "KEY_ESC"


def enter2scancode():
    return "KEY_ENTER"


def backspace2scancode():
    return "KEY_BACKSPACE"


def f6_2scancode():
    return "KEY_F6"


def keyboard_push_scancode(vm_name, code_string):
    code = code_string.split(' ')
    vm.virsh("send-key", vm_name, "--codeset", "linux", *code)
