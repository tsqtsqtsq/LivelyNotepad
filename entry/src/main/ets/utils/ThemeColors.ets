// ThemeColors.ets
// Unified theme color system — replaces hardcoded color values throughout the app.
// Based on HarmonyOS spacing system: 4, 8, 12, 16, 24

export interface ThemeColors {
  bg: string;               // 主背景
  surface: string;          // 卡片 / 面板背景
  border: string;           // 分割线 / 边框
  text: string;             // 主文本色
  textSecondary: string;    // 次要文本色（行号、提示等）
  accent: string;           // 强调色（查找匹配高亮等）
  accentBg: string;         // 强调色背景（半透明）
  inputBg: string;          // 输入框 / TextArea 背景
  hoverBg: string;          // 按钮悬停色
  activeBg: string;         // 按钮激活态色
  gutterBg: string;         // 行号 / 折叠列背景
  caretColor: string;       // 光标颜色
  selectionColor: string;   // 选中文本背景色
  tabActiveBg: string;      // 激活的 Tab 背景
  tabInactiveBg: string;    // 未激活的 Tab 背景
  tabBorder: string;        // Tab 底部高亮条
  statusBarBg: string;      // 状态栏背景
  statusBarText: string;    // 状态栏文字
  highlightFind: string;    // 查找当前匹配
  highlightFindAll: string; // 查找所有匹配
  divider: string;          // 分割线（工具栏分隔符）
  searchMark: string;       // 搜索装饰线颜色
  bracketMatchBg: string;   // 括号匹配高亮背景
  currentLineBg: string;    // 当前行高亮背景
  indentGuide: string;      // 缩进引导线颜色
  danger: string;           // 危险操作颜色
}

export const DARK_THEME: ThemeColors = {
  bg: '#1E1E1E',
  surface: '#252526',
  border: '#3C3C3C',
  text: '#D4D4D4',
  textSecondary: '#858585',
  accent: '#0098FF',
  accentBg: 'rgba(0, 152, 255, 0.25)',
  inputBg: '#1E1E1E',
  hoverBg: '#2A2D2E',
  activeBg: '#37373D',
  gutterBg: '#1E1E1E',
  caretColor: '#AEAFAD',
  selectionColor: '#264F78',
  tabActiveBg: '#1E1E1E',
  tabInactiveBg: '#2D2D2D',
  tabBorder: '#007ACC',
  statusBarBg: '#252526',
  statusBarText: '#858585',
  highlightFind: 'rgba(0, 152, 255, 0.6)',
  highlightFindAll: 'rgba(0, 152, 255, 0.3)',
  divider: '#444444',
  searchMark: '#FF6666',
  bracketMatchBg: 'rgba(255, 255, 255, 0.12)',
  currentLineBg: 'rgba(255, 255, 255, 0.08)',
  indentGuide: '#3C3C3C',
  danger: '#F44747'
};

export const LIGHT_THEME: ThemeColors = {
  bg: '#FFFFFF',
  surface: '#F3F3F3',
  border: '#E0E0E0',
  text: '#1F1F1F',
  textSecondary: '#8B8B8B',
  accent: '#007ACC',
  accentBg: 'rgba(0, 122, 204, 0.12)',
  inputBg: '#FFFFFF',
  hoverBg: '#E8E8E8',
  activeBg: '#D6D6D6',
  gutterBg: '#F5F5F5',
  caretColor: '#1F1F1F',
  selectionColor: '#ADD6FF',
  tabActiveBg: '#FFFFFF',
  tabInactiveBg: '#ECECEC',
  tabBorder: '#007ACC',
  statusBarBg: '#E8E8E8',
  statusBarText: '#555555',
  highlightFind: 'rgba(0, 122, 204, 0.5)',
  highlightFindAll: 'rgba(0, 122, 204, 0.2)',
  divider: '#D0D0D0',
  searchMark: '#FF0000',
  bracketMatchBg: 'rgba(0, 0, 0, 0.08)',
  currentLineBg: 'rgba(0, 0, 220, 0.08)',
  indentGuide: '#D0D0D0',
  danger: '#E84040'
};

export function getTheme(dark: boolean): ThemeColors {
  return dark ? DARK_THEME : LIGHT_THEME;
}

export namespace ThemeColors {
  export function forMode(mode: string): ThemeColors {
    return mode === 'dark' ? DARK_THEME : LIGHT_THEME;
  }
}