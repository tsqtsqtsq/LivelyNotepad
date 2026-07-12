export class CommandItem {
  label: string;
  desc: string;
  key: string;
  constructor(label: string, desc: string, key: string) {
    this.label = label;
    this.desc = desc;
    this.key = key;
  }
}

export class SymbolItem {
  label: string;
  line: number;
  kind: string;
  constructor(label: string, line: number, kind: string) {
    this.label = label;
    this.line = line;
    this.kind = kind;
  }
}

export const COMMANDS: CommandItem[] = [
  new CommandItem('保存文件', '保存当前文件', 'Ctrl+S'),
  new CommandItem('撤销', '撤销上次编辑', 'Ctrl+Z'),
  new CommandItem('重做', '重做已撤销的编辑', 'Ctrl+Y'),
  new CommandItem('查找替换', '打开查找替换栏', 'Ctrl+F'),
  new CommandItem('转到行', '跳转到指定行号', 'Ctrl+G'),
  new CommandItem('全部折叠', '折叠所有代码块', ''),
  new CommandItem('展开全部', '展开所有折叠', ''),
  new CommandItem('切换行号', '显示/隐藏行号', ''),
  new CommandItem('切换自动换行', '开启/关闭自动换行', ''),
  new CommandItem('切换注释', '行注释切换', 'Ctrl+/'),
  new CommandItem('复制当前行', '复制光标所在行', 'Ctrl+D'),
  new CommandItem('删除当前行', '删除光标所在行', 'Ctrl+Shift+K'),
  new CommandItem('上移当前行', '当前行向上移动', 'Ctrl+Shift+↑'),
  new CommandItem('下移当前行', '当前行向下移动', 'Ctrl+Shift+↓'),
  new CommandItem('放大字体', '增大编辑器字号', 'Ctrl+='),
  new CommandItem('缩小字体', '减小编辑器字号', 'Ctrl+-'),
  new CommandItem('重置缩放', '恢复默认字号', 'Ctrl+0'),
  new CommandItem('插入日期时间', '插入当前日期时间', ''),
  new CommandItem('快捷键参考', '显示所有快捷键', 'F1'),
  new CommandItem('选中整行', '选中光标所在整行', 'Ctrl+L'),
  new CommandItem('跳转匹配括号', '跳转到匹配的括号', 'Ctrl+['),
  new CommandItem('复制行到下方', '向下插入空行', 'Ctrl+Enter'),
  new CommandItem('复制行到上方', '向上插入空行', 'Ctrl+Shift+Enter'),
];

export const SNIPPETS_CPP: Record<string, string> = {
  'fori': 'for (int i = 0; i < n; i++) {\n\t\n}',
  'fore': 'for (auto &x : v) {\n\t\n}',
  'if': 'if (condition) {\n\t\n}',
  'else': 'else {\n\t\n}',
  'main': 'int main() {\n\treturn 0;\n}',
  'class': 'class name {\npublic:\n\t\n};',
  'struct': 'struct name {\n\t\n};',
  'while': 'while (condition) {\n\t\n}',
  'switch': 'switch (x) {\ncase 1:\n\tbreak;\ndefault:\n\tbreak;\n}',
  'cout': 'std::cout <<  << std::endl;',
  'vector': 'std::vector<type> v;',
};

export const SNIPPETS_PYTHON: Record<string, string> = {
  'def': 'def name():\n\t\n',
  'for': 'for x in iterable:\n\t\n',
  'if': 'if condition:\n\t\n',
  'class': 'class name:\n\t\n',
  'while': 'while condition:\n\t\n',
  'try': 'try:\n\t\nexcept:\n\t\n',
  'with': 'with open("file", "r") as f:\n\t\n',
};

export const SNIPPETS_ARKTS: Record<string, string> = {
  'func': 'function name() {\n\t\n}',
  'for': 'for (let i = 0; i < n; i++) {\n\t\n}',
  'forof': 'for (const item of list) {\n\t\n}',
  'if': 'if (condition) {\n\t\n}',
  'else': 'else {\n\t\n}',
  'class': '@Observed\nclass name {\n\t\n}',
  'struct': '@Component\nstruct name {\n\tbuild() {\n\t}\n}',
  'switch': 'switch (x) {\n\tcase 1:\n\t\tbreak;\n\tdefault:\n\t\tbreak;\n}',
};

export const MINIMAP_KW: Set<string> = new Set([
  'int', 'void', 'class', 'struct', 'if', 'else', 'for', 'while',
  'return', 'const', 'static', 'def', 'function', 'import', 'from',
  'public', 'private', 'protected', 'try', 'catch', 'throw',
  'new', 'this', 'super', 'enum', 'switch', 'case', 'break',
  'continue', 'do', 'goto', 'using', 'namespace', 'template',
  'let', 'var', 'async', 'await', 'export', 'default', 'extends',
  'implements', 'interface', 'type', 'readonly', 'abstract'
]);

export const BRACKET_COLORS: string[] = [
  '#FFD700', '#DA70D6', '#00CED1', '#FF6B6B', '#87CEEB', '#FFA500'
];

export const WORD_SEP_CHARS: Set<string> = new Set('`~!@#$%^&*()-=+[{]}\\|;:\'",.<>/?'.split(''));
