export interface SessionTabRecord {
  id: string;
  label: string;
  filePath: string;
  content: string;
  language: string;
  isModified: boolean;
  encoding: string;
  cursorLine: number;
  cursorColumn: number;
}

export interface SessionRecord {
  activeTabId: string;
  tabs: SessionTabRecord[];
}
