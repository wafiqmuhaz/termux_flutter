final class TerminalKeys {
  const TerminalKeys._();

  static const arrowUp = '\x1b[A';
  static const arrowDown = '\x1b[B';
  static const arrowRight = '\x1b[C';
  static const arrowLeft = '\x1b[D';
  static const home = '\x1b[H';
  static const end = '\x1b[F';
  static const pageUp = '\x1b[5~';
  static const pageDown = '\x1b[6~';
  static const insert = '\x1b[2~';
  static const delete = '\x1b[3~';

  static String bracketedPaste(String text) => '\x1b[200~$text\x1b[201~';
}
