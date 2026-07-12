import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LineEndingType } from '../model/TabModel';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 文件读写服务 - 封装 HarmonyOS 文件系统 API（异步 I/O）
 * 负责文件的打开、保存、另存为等操作
 */
export class FileService {
  static async readFile(filePath: string, encoding: string = 'utf-8'): Promise<string> {
    let file: fileIo.File | undefined;
    try {
      file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(filePath);
      if (stat.size === 0) {
        return '';
      }
      const buffer = new ArrayBuffer(stat.size);
      const readLen = await fileIo.read(file.fd, buffer);
      const decoder = new util.TextDecoder(encoding);
      const content: string = decoder.decodeToString(new Uint8Array(buffer, 0, readLen));
      return content;
    } catch (err) {
      const msg = err instanceof Error ? (err as Error).message : String(err);
      throw new Error('读取文件失败: ' + msg);
    } finally {
      if (file) {
        try { await fileIo.close(file); } catch (e) {
          hilog.warn(0x0000, 'FileService', 'Failed to close read file: %{public}s', String(e));
        }
      }
    }
  }

  static async writeFile(filePath: string, content: string): Promise<void> {
    let file: fileIo.File | undefined;
    try {
      file = await fileIo.open(filePath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const encoder = new util.TextEncoder();
      const buffer: Uint8Array = encoder.encodeInto(content);
      await fileIo.write(file.fd, buffer);
    } catch (err) {
      const msg = err instanceof Error ? (err as Error).message : String(err);
      throw new Error('保存文件失败: ' + msg);
    } finally {
      if (file) {
        try { await fileIo.close(file); } catch (e) {
          hilog.warn(0x0000, 'FileService', 'Failed to close write file: %{public}s', String(e));
        }
      }
    }
  }

  static getFileName(fullPath: string): string {
    if (!fullPath) return '新建文件';
    const lastSlash = fullPath.lastIndexOf('/');
    const lastBackslash = fullPath.lastIndexOf('\\');
    const lastSep = Math.max(lastSlash, lastBackslash);
    if (lastSep >= 0) return fullPath.substring(lastSep + 1);
    return fullPath;
  }

  static getDirectoryPath(fullPath: string): string {
    if (!fullPath) return '';
    const lastSlash = fullPath.lastIndexOf('/');
    const lastBackslash = fullPath.lastIndexOf('\\');
    const lastSep = Math.max(lastSlash, lastBackslash);
    if (lastSep >= 0) return fullPath.substring(0, lastSep);
    return '';
  }

  static detectLineEnding(content: string): LineEndingType {
    if (!content || content.length === 0) {
      return LineEndingType.LF;
    }

    let crlfCount = 0;
    let lfCount = 0;
    let crCount = 0;

    for (let i = 0; i < content.length; i++) {
      if (content.charAt(i) === '\r') {
        if (i + 1 < content.length && content.charAt(i + 1) === '\n') {
          crlfCount++;
          i++;
        } else {
          crCount++;
        }
      } else if (content.charAt(i) === '\n') {
        lfCount++;
      }
    }

    if (crlfCount >= lfCount && crlfCount >= crCount) {
      return LineEndingType.CRLF;
    }
    if (crCount >= lfCount && crCount >= crlfCount) {
      return LineEndingType.CR;
    }
    return LineEndingType.LF;
  }
}
