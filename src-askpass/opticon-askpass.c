// Copyright 2014 George King.
// Permission to use this file is granted in license-opticon.txt (ISC license).

// program to serve as SUDO_ASKPASS helper.
// SUDO_ASKPASS is an environment variable respected by sudo;
// if it is set, then the specified program is called; it must prompt the user for the password, and print it to stdout.
// sudo will read the askpass output and proceed.

// this implementation uses carbon's secure text entry mechanism to prevent your user password from being logged by opticon,
// or any other event tap.

// to use this, add the following to your .bashrc / .bash_profile:
//  export SUDO_ASKPASS=~/bin/opticon-askpass # or whatever install path you choose.
//  alias sudo='sudo -A' # make sudo use SUDO_ASKPASS.


#import <stdio.h>
#import <signal.h>
#import <termios.h>
#import <Carbon/Carbon.h>

// defined for debugging only.
#define errFL(msg, ...) fprintf(stderr, msg "\n", ## __VA_ARGS__)

// signal handling.
// we catch SIGINT so that we can restore the terminal echo, and also exit cleanly without any output.
// the OSX 10.9 sudo-72 implementation interprets a clean exit with no output as 'cancel', and does not retry.
bool interrupted = false;

void sig_handler(int sig) {
  // TODO: should we be catching any other signals?
  interrupted = true;
}


int main(int argc, const char * argv[]) {
  // setup handler for SIGINT.
  struct sigaction action;
  sigemptyset(&action.sa_mask);
  action.sa_handler = sig_handler;
  sigaction(SIGINT, &action, NULL);
  // print prompt.
  fputs("⎉ ", stderr); // U+2389 CIRCLED HORIZONTAL BAR WITH NOTCH.
  fflush(stderr); // flush so that the prompt displays immediately (we did not print a newline).
  // turn off terminal echo.
  struct termios std_state, silent_state;
  int stdin_fdesc = fileno(stdin);
  int code = tcgetattr(stdin_fdesc, &std_state);
  if (code) return code;
  silent_state = std_state;
  silent_state.c_lflag &= ~ECHO;
  code = tcsetattr(stdin_fdesc, TCSADRAIN, &silent_state);
  if (code) return code;
  // turn on secure input.
  EnableSecureEventInput();
  // read the entire password in, and only output once complete.
  // this way if the user interrupts with ctrl-c, sudo receives an empty string and aborts,
  // rather than retrying.
  const int len_buffer = 256; // same as OSX 10.9 sudo-72 implementation.
  char buffer[len_buffer];
  int len = 0;
  while (len < len_buffer) {
    if (interrupted) {
      goto finish;
    }
    char c = getchar();
    if (c == EOF) {
      goto finish;
    }
    buffer[len++] = c;
    if (c == '\n') break;
  }
  fwrite(buffer, 1, len, stdout);
  fflush(stdout);
  // reset state.
finish:
  DisableSecureEventInput(); // unnecessary?
  code = tcsetattr(stdin_fdesc, TCSADRAIN, &std_state);
  return code;
}

