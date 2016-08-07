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
        'A': "KEY_SHIFT KEY_A",
        'B': "KEY_SHIFT KEY_B",
        'C': "KEY_SHIFT KEY_C",
        'D': "KEY_SHIFT KEY_D",
        'E': "KEY_SHIFT KEY_E",
        'F': "KEY_SHIFT KEY_F",
        'G': "KEY_SHIFT KEY_G",
        'H': "KEY_SHIFT KEY_H",
        'I': "KEY_SHIFT KEY_I",
        'J': "KEY_SHIFT KEY_J",
        'K': "KEY_SHIFT KEY_K",
        'L': "KEY_SHIFT KEY_L",
        'M': "KEY_SHIFT KEY_M",
        'N': "KEY_SHIFT KEY_N",
        'O': "KEY_SHIFT KEY_O",
        'P': "KEY_SHIFT KEY_P",
        'Q': "KEY_SHIFT KEY_Q",
        'R': "KEY_SHIFT KEY_R",
        'S': "KEY_SHIFT KEY_S",
        'T': "KEY_SHIFT KEY_T",
        'U': "KEY_SHIFT KEY_U",
        'V': "KEY_SHIFT KEY_V",
        'W': "KEY_SHIFT KEY_W",
        'X': "KEY_SHIFT KEY_X",
        'Y': "KEY_SHIFT KEY_Y",
        'Z': "KEY_SHIFT KEY_Z",
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
        '!': "KEY_SHIFT KEY_1",
        '@': "KEY_SHIFT KEY_2",
        '#': "KEY_SHIFT KEY_3",
        '$': "KEY_SHIFT KEY_4",
        '%': "KEY_SHIFT KEY_5",
        '^': "KEY_SHIFT KEY_6",
        '&': "KEY_SHIFT KEY_7",
        '*': "KEY_SHIFT KEY_8",
        '(': "KEY_SHIFT KEY_9",
        ')': "KEY_SHIFT KEY_0",
        '-': "KEY_MINUS",
        '_': "KEY_SHIFT KEY_MINUS",
        '=': "KEY_EQUAL",
        '+': "KEY_SHIFT KEY_EQUAL",
        ' ': "KEY_SPACE",
        '[': "KEY_LEFTBRACE",
        ']': "KEY_RIGHTBRACE",
        '{': "KEY_SHIFT KEY_LEFTBRACE",
        '}': "KEY_SHIFT KEY_RIGHTBRACE",
        ';': "KEY_SEMICOLON",
        ':': "KEY_SHIFT KEY_SEMICOLON",
        ',': "KEY_COMMA",
        '.': "KEY_DOT",
        '/': "KEY_SLASH",
        '\\': "KEY_BACKSLASH",
        '|': "KEY_SHIFT KEY_BACKSLASH",
        '?': "KEY_SHIFT KEY_SLASH",
        '"': "KEY_SHIFT KEY_APOSTROPHE",
        "'": "KEY_APOSTROPHE",
        ">": "KEY_SHIFT KEY_DOT",
        "<": "KEY_SHIFT KEY_COMMA"
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
