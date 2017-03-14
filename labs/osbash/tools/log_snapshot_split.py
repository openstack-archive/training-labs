#!/usr/bin/env python

"""

This script splits out log file portions based on full log files and
"ls -l" snapshots that document their size at various points in time.

"""

# Force Python 2 to use float division even for ints
from __future__ import division
from __future__ import print_function

import argparse
import errno
import mmap
import os
import sys

from glob import glob

# Extension of directory snapshot files
SNAP_EXT = "lsl"


def get_destdir(destdir, name):
    """Return destination directory for results of current snapshot."""

    # Remove extension from name
    basename = os.path.splitext(name)[0]

    dir_path = os.path.join(destdir, basename)

    # Sanity check: we don't want to overwrite exisiting results.
    if os.path.exists(dir_path):
        print("ERROR: destination directory already exists:", dir_path)
        sys.exit(1)

    return dir_path


def get_file_slice(path, old_size, size):
    """Get the content from first to second byte counter of given file."""
    with open(path, "r+b") as fin:
        try:
            mmp = mmap.mmap(fin.fileno(), 0)
        except ValueError as err:
            if os.path.getsize(path) == 0:
                # Log file is empty, nothing to mmap or read
                return None
            else:
                # Some other error, pass it on
                raise err
        else:
            mmp.seek(old_size)
            return mmp.read(size - old_size)


def create_parent_dirs_for(file_path):
    """Create parent directories for given file or directory."""
    dir_path = os.path.dirname(file_path)
    try:
        os.makedirs(dir_path)
    except OSError as err:
        if err.errno == errno.EEXIST and os.path.isdir(dir_path):
            pass
        else:
            raise


def get_size_and_path(line):
    """From a 'ls -l' line, return columns 4 (size) and 8 (path)."""
    cols = line.split()
    size, path = (int(cols[4]), cols[8])
    return size, path


def get_ls_snap_files_from_dir(snapdir):
    """Get paths of all 'ls -l' snapshot files in given directory."""
    # Return them sorted so they get processed in order
    return sorted(glob(os.path.join(snapdir, "*." + SNAP_EXT)))


def get_ls_snap_files_from_path(snap_paths, verbose):
    """Get paths of all 'ls -l' snapshot files."""
    ls_snap_files = []

    for path in snap_paths:
        if os.path.isdir(path):
            if len(snap_paths) > 1:
                print("ERROR LS_SNAP_PATH contains a directory and additional "
                      "paths. Aborting.")
                sys.exit(1)
            ls_snap_files = get_ls_snap_files_from_dir(path)
            break
        elif os.path.isfile(path):
            ls_snap_files.append(path)
        else:
            print("Bad argument: ", path)
            sys.exit(1)

    if verbose:
        print("LS_SNAP_PATH ", snap_paths)
        print("'ls -l' snapshot files ", ls_snap_files)

    return ls_snap_files


def get_log_and_result_dirs(args):
    """Return paths to log and result directories."""
    if os.path.isdir(args.ls_snap_path[0]):
        snapdir = args.ls_snap_path[0]
    else:
        snapdir = os.path.dirname(args.ls_snap_path[0])

    if args.logdir is None:
        logdir = snapdir
    else:
        logdir = args.logdir

    if args.resultdir is None:
        # If no destination directory is given, use a subdir in the snapdir
        resultdir = os.path.join(snapdir, "split_logs")
    else:
        resultdir = args.resultdir

    if args.verbose:
        print("LOG_DIR ", logdir)
        print("RESULTS_DIR", resultdir)

    return logdir, resultdir


def write_results(result_path, new_lines):
    """Create one split out log file (and any parent directories)."""
    # Create parent directories (if any) for current log file
    create_parent_dirs_for(result_path)

    with open(result_path, "w") as fout:
        # If the log file was empty at this point, skip writing
        # new_lines (Empty) to the split out file.
        if new_lines:
            fout.write(new_lines)


def indicate_new_snapshot(snap_name, verbose):
    """Indicate progress by printing name (verbose) or a dot."""
    if verbose:
        print(snap_name)
    else:
        # Print dots to indicate progress
        print('.', end='')
        sys.stdout.flush()


def process_snap_files(ls_snap_files, args):
    """Read snapshot files and create split out log files."""

    logdir, resultdir = get_log_and_result_dirs(args)

    # For each log file, number of bytes handled so far
    log_size = dict()

    for ls_snap_file in ls_snap_files:

        snap_name = os.path.basename(ls_snap_file)

        indicate_new_snapshot(snap_name, args.verbose)

        with open(ls_snap_file, "r") as ls_snap_content:

            # Create directory for results of this log snapshot
            dest_subdir = get_destdir(resultdir, snap_name)

            for ls_line in ls_snap_content:
                new_size, log_path = get_size_and_path(ls_line)
                # If the path in the "ls -l" files is absolute, make it
                # relative; os.path.join would ignore the target directory path
                # otherwise
                log_rpath = log_path.strip("/")


                if args.verbose:
                    print("\t", log_rpath)

                if log_rpath not in log_size:
                    # New log file
                    log_size[log_rpath] = 0
                elif log_size[log_rpath] == new_size:
                    # Log file did not change, skip
                    continue

                src_log = os.path.join(logdir, log_rpath)
                new_lines = get_file_slice(src_log, log_size[log_rpath],
                                           new_size)

                log_size[log_rpath] = new_size

                result_path = os.path.join(dest_subdir, log_rpath)
                write_results(result_path, new_lines)

    if not args.verbose:
        # New line after last period of progress indicator
        print('')


def main():
    parser = argparse.ArgumentParser(description="Split log files according to"
                                                 " 'ls -l' snapshots.")
    parser.add_argument('ls_snap_path', metavar='LS_SNAP_PATH', nargs='+',
                        help="'ls -l' snapshot files or directory containing"
                             " them")
    parser.add_argument('--logdir', metavar='LOG_DIR', nargs='?',
                        help="Root directory for log files (default: "
                             "LS_SNAP_PATH)")
    parser.add_argument('--resultdir', metavar='RESULT_DIR', nargs='?',
                        help="Target directory for results (default: "
                             "LS_SNAP_PATH/split_logs)")
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()

    ls_snap_files = get_ls_snap_files_from_path(args.ls_snap_path,
                                                args.verbose)

    process_snap_files(ls_snap_files, args)


if __name__ == "__main__":
    sys.exit(main())
