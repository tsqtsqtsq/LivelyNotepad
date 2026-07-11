import { ProgrammingLanguage } from '../model/TabModel';

/**
 * 语法高亮器（参考 VS Code / Notepad++ 分词着色原理）
 * 将文本按 Token 类型拆分，每种 Token 对应一种颜色
 */

export interface Token {
  text: string;
  type: TokenType;
}

export enum TokenType {
  NORMAL,
  KEYWORD,
  STRING,
  COMMENT,
  NUMBER,
  FUNCTION,
  OPERATOR,
  PREPROCESSOR
}

/** 各语言关键字集合 */
const KEYWORDS = new Map<string, Set<string>>();
KEYWORDS.set('javascript', new Set([
  'const', 'let', 'var', 'function', 'return', 'if', 'else',
  'for', 'while', 'do', 'switch', 'case', 'break', 'continue',
  'new', 'this', 'class', 'extends', 'import', 'export', 'from',
  'async', 'await', 'try', 'catch', 'throw', 'finally', 'typeof',
  'instanceof', 'in', 'of', 'true', 'false', 'null', 'undefined',
  'default', 'yield', 'delete', 'void', 'with', 'debugger', 'static',
  'get', 'set', 'super', 'constructor'
]));
KEYWORDS.set('typescript', new Set([
  'const', 'let', 'var', 'function', 'return', 'if', 'else',
  'for', 'while', 'do', 'switch', 'case', 'break', 'continue',
  'new', 'this', 'class', 'extends', 'import', 'export', 'from',
  'async', 'await', 'try', 'catch', 'throw', 'finally', 'typeof',
  'instanceof', 'in', 'of', 'true', 'false', 'null', 'undefined',
  'type', 'interface', 'enum', 'readonly', 'as', 'is', 'keyof',
  'public', 'private', 'protected', 'abstract', 'implements',
  'static', 'get', 'set', 'super', 'constructor', 'declare', 'module'
]));
KEYWORDS.set('arkts', new Set([
  'const', 'let', 'var', 'function', 'return', 'if', 'else',
  'for', 'while', 'do', 'switch', 'case', 'break', 'continue',
  'new', 'this', 'class', 'extends', 'import', 'export', 'from',
  'async', 'await', 'try', 'catch', 'throw', 'finally', 'typeof',
  'true', 'false', 'null', 'undefined', 'type', 'interface',
  'enum', 'readonly', 'as', 'private', 'static', 'struct',
  '@State', '@Prop', '@Link', '@Entry', '@Component', '@Builder',
  'void', 'string', 'number', 'boolean', 'Array'
]));
KEYWORDS.set('python', new Set([
  'def', 'return', 'if', 'elif', 'else', 'for', 'while',
  'import', 'from', 'as', 'class', 'try', 'except', 'finally',
  'raise', 'with', 'yield', 'lambda', 'pass', 'break', 'continue',
  'in', 'is', 'not', 'and', 'or', 'True', 'False', 'None',
  'global', 'nonlocal', 'assert', 'del'
]));
KEYWORDS.set('java', new Set([
  'public', 'private', 'protected', 'static', 'final', 'abstract',
  'class', 'interface', 'extends', 'implements', 'new', 'return',
  'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break',
  'continue', 'try', 'catch', 'throw', 'throws', 'import', 'package',
  'void', 'int', 'long', 'double', 'float', 'boolean', 'char',
  'byte', 'short', 'String', 'true', 'false', 'null', 'this', 'super',
  'enum', 'default', 'synchronized', 'volatile', 'transient', 'native'
]));
KEYWORDS.set('c', new Set([
  'int', 'long', 'double', 'float', 'char', 'short', 'void',
  'unsigned', 'signed', 'const', 'static', 'extern', 'volatile',
  'register', 'auto', 'if', 'else', 'for', 'while', 'do',
  'switch', 'case', 'break', 'continue', 'return', 'goto',
  'struct', 'union', 'enum', 'typedef', 'sizeof', 'NULL',
  'true', 'false', 'include', 'define', 'ifdef', 'ifndef', 'endif'
]));
KEYWORDS.set('cpp', new Set([
  'int', 'long', 'double', 'float', 'char', 'short', 'void',
  'unsigned', 'signed', 'const', 'static', 'extern', 'volatile',
  'bool', 'auto', 'if', 'else', 'for', 'while', 'do',
  'switch', 'case', 'break', 'continue', 'return', 'goto',
  'struct', 'class', 'union', 'enum', 'typedef', 'sizeof',
  'new', 'delete', 'this', 'virtual', 'override', 'final',
  'public', 'private', 'protected', 'namespace', 'using',
  'template', 'typename', 'true', 'false', 'nullptr', 'throw',
  'try', 'catch', 'include', 'define', 'constexpr', 'noexcept',
  'explicit', 'mutable', 'friend', 'operator', 'inline'
]));
KEYWORDS.set('go', new Set([
  'func', 'return', 'if', 'else', 'for', 'range', 'switch',
  'case', 'break', 'continue', 'var', 'const', 'type', 'struct',
  'interface', 'map', 'chan', 'import', 'package', 'go', 'defer',
  'select', 'fallthrough', 'goto', 'nil', 'true', 'false',
  'int', 'string', 'bool', 'float64', 'float32', 'byte', 'error',
  'make', 'new', 'append', 'len', 'cap', 'copy', 'delete', 'close',
  'panic', 'recover', 'range'
]));
KEYWORDS.set('rust', new Set([
  'fn', 'let', 'mut', 'const', 'static', 'if', 'else', 'match',
  'for', 'while', 'loop', 'in', 'return', 'break', 'continue',
  'struct', 'enum', 'trait', 'impl', 'pub', 'use', 'mod', 'crate',
  'self', 'super', 'where', 'as', 'ref', 'move', 'async', 'await',
  'unsafe', 'dyn', 'true', 'false', 'type', 'fn', 'macro_rules'
]));
KEYWORDS.set('sql', new Set([
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'UPDATE', 'DELETE', 'CREATE',
  'TABLE', 'DROP', 'ALTER', 'INDEX', 'JOIN', 'LEFT', 'RIGHT', 'INNER',
  'OUTER', 'ON', 'AND', 'OR', 'NOT', 'IN', 'LIKE', 'BETWEEN',
  'IS', 'NULL', 'AS', 'ORDER', 'BY', 'GROUP', 'HAVING', 'LIMIT',
  'OFFSET', 'UNION', 'ALL', 'DISTINCT', 'COUNT', 'SUM', 'AVG',
  'MAX', 'MIN', 'SET', 'VALUES', 'INTO', 'PRIMARY', 'KEY', 'FOREIGN',
  'REFERENCES', 'CASCADE', 'DEFAULT', 'CHECK', 'UNIQUE', 'CONSTRAINT',
  'INT', 'VARCHAR', 'TEXT', 'BOOLEAN', 'DATE', 'TIMESTAMP', 'FLOAT'
]));
KEYWORDS.set('shell', new Set([
  'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done',
  'case', 'esac', 'in', 'function', 'return', 'exit', 'export',
  'local', 'readonly', 'unset', 'echo', 'source', 'alias', 'eval',
  'exec', 'shift', 'trap', 'set'
]));
KEYWORDS.set('html', new Set([]));
KEYWORDS.set('css', new Set([]));
KEYWORDS.set('json', new Set(['true', 'false', 'null']));
KEYWORDS.set('xml', new Set([]));
KEYWORDS.set('markdown', new Set([]));
KEYWORDS.set('yaml', new Set(['true', 'false', 'null', 'yes', 'no', 'on', 'off']));
KEYWORDS.set('csharp', new Set([
  'using', 'namespace', 'class', 'struct', 'interface', 'enum',
  'public', 'private', 'protected', 'internal', 'static', 'readonly',
  'const', 'virtual', 'override', 'abstract', 'sealed', 'async',
  'await', 'new', 'this', 'base', 'return', 'if', 'else', 'for',
  'foreach', 'while', 'do', 'switch', 'case', 'break', 'continue',
  'try', 'catch', 'throw', 'finally', 'var', 'int', 'string',
  'bool', 'double', 'float', 'long', 'char', 'void', 'null',
  'true', 'false', 'typeof', 'is', 'as', 'in', 'out', 'ref'
]));
KEYWORDS.set('swift', new Set([
  'let', 'var', 'func', 'return', 'if', 'else', 'for', 'in',
  'while', 'switch', 'case', 'break', 'continue', 'class',
  'struct', 'enum', 'protocol', 'extension', 'import', 'as',
  'self', 'Self', 'super', 'init', 'deinit', 'guard', 'where',
  'static', 'public', 'private', 'fileprivate', 'internal',
  'open', 'final', 'override', 'mutating', 'nonmutating',
  'throws', 'rethrows', 'try', 'catch', 'throw', 'do'
]));
KEYWORDS.set('kotlin', new Set([
  'val', 'var', 'fun', 'class', 'interface', 'object', 'data',
  'sealed', 'enum', 'when', 'if', 'else', 'for', 'while', 'do',
  'return', 'break', 'continue', 'try', 'catch', 'finally',
  'throw', 'import', 'package', 'as', 'is', '!is', 'in', '!in',
  'this', 'super', 'true', 'false', 'null', 'typealias',
  'companion', 'internal', 'private', 'protected', 'public',
  'abstract', 'open', 'final', 'override', 'lateinit', 'by',
  'lazy', 'suspend', 'constructor', 'init', 'annotation'
]));
KEYWORDS.set('toml', new Set([
  'true', 'false'
]));
KEYWORDS.set('plaintext', new Set([]));

/** 操作符集合 */
const OPERATORS = new Set([
  '=', '==', '!=', '<', '>', '<=', '>=', '+', '-', '*', '/',
  '%', '++', '--', '+=', '-=', '*=', '/=', '&&', '||', '!',
  '&', '|', '^', '~', '<<', '>>', '=>', '->', '::',
  '??', '?.', '...'
]);

export class Highlighter {
  /** 将源代码拆分为着色 Token 数组 */
  static tokenize(text: string, lang: ProgrammingLanguage): Token[] {
    const tokens: Token[] = [];
    const kwSet = KEYWORDS.get(lang);
    const keywords = kwSet !== undefined ? kwSet : new Set<string>();
    let i = 0;

    while (i < text.length) {
      // 预处理指令（C/C++/C#）: #include, #define, #ifdef 等
      if ((lang === ProgrammingLanguage.CPP ||
          lang === ProgrammingLanguage.C ||
          lang === ProgrammingLanguage.CSHARP) &&
          (i === 0 || text.charAt(i - 1) === '\n') &&
          (text.charAt(i) === '#' || (text.charAt(i) === ' ' || text.charAt(i) === '\t') &&
            i + 1 < text.length && text.charAt(i + 1) === '#')) {
        // 跳过前导空白
        let start = i;
        while (start < text.length &&
               (text.charAt(start) === ' ' ||
                text.charAt(start) === '\t')) {
          start++;
        }
        let end = start + 1;
        while (end < text.length && text.charAt(end) !== '\n') end++;
        tokens.push({ text: text.substring(start, end), type: TokenType.PREPROCESSOR });
        i = end;
        continue;
      }

      // 单行注释 //
      if ((lang === ProgrammingLanguage.JAVASCRIPT ||
          lang === ProgrammingLanguage.TYPESCRIPT ||
          lang === ProgrammingLanguage.ARKTS ||
          lang === ProgrammingLanguage.CPP ||
          lang === ProgrammingLanguage.C ||
          lang === ProgrammingLanguage.CSHARP ||
          lang === ProgrammingLanguage.GO ||
          lang === ProgrammingLanguage.RUST ||
          lang === ProgrammingLanguage.SWIFT ||
          lang === ProgrammingLanguage.JAVA) &&
          i + 1 < text.length &&
          text.charAt(i) === '/' && text.charAt(i + 1) === '/') {
        let end = i + 2;
        while (end < text.length && text.charAt(end) !== '\n') {
          end++;
        }
        tokens.push({ text: text.substring(i, end), type: TokenType.COMMENT });
        i = end;
        continue;
      }

      // 多行注释 /* */
      if ((lang === ProgrammingLanguage.JAVASCRIPT ||
          lang === ProgrammingLanguage.TYPESCRIPT ||
          lang === ProgrammingLanguage.ARKTS ||
          lang === ProgrammingLanguage.CPP ||
          lang === ProgrammingLanguage.C ||
          lang === ProgrammingLanguage.CSHARP ||
          lang === ProgrammingLanguage.GO ||
          lang === ProgrammingLanguage.RUST ||
          lang === ProgrammingLanguage.SWIFT ||
          lang === ProgrammingLanguage.JAVA) &&
          i + 1 < text.length &&
          text.charAt(i) === '/' && text.charAt(i + 1) === '*') {
        let end = i + 2;
        while (end < text.length - 1 &&
               !(text.charAt(end) === '*' &&
                 text.charAt(end + 1) === '/')) {
          end++;
        }
        if (end < text.length - 1) {
          end += 2; // 找到了 */
        } else {
          end = text.length; // 未闭合注释，包含剩余全部
        }
        tokens.push({ text: text.substring(i, end), type: TokenType.COMMENT });
        i = end;
        continue;
      }

      // Python/SHELL # 注释
      if ((lang === ProgrammingLanguage.PYTHON ||
          lang === ProgrammingLanguage.SHELL ||
          lang === ProgrammingLanguage.YAML) &&
          text.charAt(i) === '#') {
        let end = i + 1;
        while (end < text.length && text.charAt(end) !== '\n') {
          end++;
        }
        tokens.push({ text: text.substring(i, end), type: TokenType.COMMENT });
        i = end;
        continue;
      }

      // HTML 注释 <!-- -->
      if (lang === ProgrammingLanguage.HTML && i + 3 < text.length && text.charAt(i) === '<' &&
          text.charAt(i + 1) === '!' && text.charAt(i + 2) === '-' && text.charAt(i + 3) === '-') {
        let end = i + 4;
        while (end < text.length - 2 &&
               !(text.charAt(end) === '-' &&
                 text.charAt(end + 1) === '-' &&
                 text.charAt(end + 2) === '>')) {
          end++;
        }
        if (end < text.length - 2) {
          end += 3; // 找到了 -->
        } else {
          end = text.length; // 未闭合注释，包含剩余全部
        }
        tokens.push({ text: text.substring(i, end), type: TokenType.COMMENT });
        i = end;
        continue;
      }

      // 字符串 "..." 或 '...'
      if (text.charAt(i) === '"' || text.charAt(i) === '\'') {
        const quote = text.charAt(i);
        let end = i + 1;
        while (end < text.length && text.charAt(end) !== quote) {
          if (text.charAt(end) === '\\') {
            end++;
          }
          end++;
        }
        if (end < text.length) {
          end++;
        }
        tokens.push({ text: text.substring(i, end), type: TokenType.STRING });
        i = end;
        continue;
      }

      // 模板字符串 `...`
      if (text.charAt(i) === '`') {
        let end = i + 1;
        while (end < text.length && text.charAt(end) !== '`') {
          if (text.charAt(end) === '\\') {
            end++;
          }
          end++;
        }
        if (end < text.length) {
          end++;
        }
        tokens.push({ text: text.substring(i, end), type: TokenType.STRING });
        i = end;
        continue;
      }

      // 数字
      if (text.charAt(i) >= '0' && text.charAt(i) <= '9') {
        let end = i;
        while (end < text.length &&
               ((text.charAt(end) >= '0' && text.charAt(end) <= '9') ||
                text.charAt(end) === '.' || text.charAt(end) === 'x' ||
                text.charAt(end) === 'X' || text.charAt(end) === 'f' ||
                (text.charAt(end) >= 'a' && text.charAt(end) <= 'f') ||
                (text.charAt(end) >= 'A' && text.charAt(end) <= 'F'))) {
          end++;
        }
        tokens.push({ text: text.substring(i, end), type: TokenType.NUMBER });
        i = end;
        continue;
      }

      // 单词（关键字或标识符）
      if (Highlighter.isWordChar(text.charAt(i))) {
        let end = i;
        while (end < text.length && Highlighter.isWordChar(text.charAt(end))) {
          end++;
        }
        const word = text.substring(i, end);
        if (keywords.has(word)) {
          tokens.push({ text: word, type: TokenType.KEYWORD });
        } else if (end < text.length && text.charAt(end) === '(') {
          tokens.push({ text: word, type: TokenType.FUNCTION });
        } else {
          tokens.push({ text: word, type: TokenType.NORMAL });
        }
        i = end;
        continue;
      }

      // 操作符（含 1~3 字符：. .. ...）
      if (OPERATORS.has(text.charAt(i)) ||
          (i + 1 < text.length && OPERATORS.has(text.substring(i, i + 2)))) {
        const op3 = text.substring(i, i + 3);
        if (i + 2 < text.length && op3 === '...') {
          tokens.push({ text: op3, type: TokenType.OPERATOR });
          i += 3;
        } else {
          const op2 = text.substring(i, i + 2);
          if (OPERATORS.has(op2)) {
            tokens.push({ text: op2, type: TokenType.OPERATOR });
            i += 2;
          } else {
            tokens.push({ text: text.charAt(i), type: TokenType.OPERATOR });
            i++;
          }
        }
        continue;
      }

      // 普通字符
      tokens.push({ text: text.charAt(i), type: TokenType.NORMAL });
      i++;
    }

    return tokens;
  }

  private static isWordChar(ch: string): boolean {
    return (ch >= 'a' && ch <= 'z') ||
           (ch >= 'A' && ch <= 'Z') ||
           ch === '_' || ch === '$';
  }
}
