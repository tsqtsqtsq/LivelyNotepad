import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { LineEndingType } from '../model/TabModel';

/**
 * 文件读写服务 - 封装 HarmonyOS 文件系统 API
 * 负责文件的打开、保存、另存为等操作
 */
export class FileService {
  static readFile(filePath: string, encoding: string = 'utf-8'): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Error) => void) => {
      let file: fileIo.File | undefined;
      try {
        file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
        const stat = fileIo.statSync(filePath);
        if (stat.size === 0) {
          resolve('');
          return;
        }
        const buffer = new ArrayBuffer(stat.size);
        const readLen = fileIo.readSync(file.fd, buffer);
        const decoder = new util.TextDecoder(encoding);
        const content: string = decoder.decodeWithStream(new Uint8Array(buffer, 0, readLen));
        resolve(content);
      } catch (err) {
        const e = err instanceof Error ? err as Error : new Error(String(err));
        reject(new Error('读取文件失败: ' + e.message));
      } finally {
        if (file) {
          try { fileIo.closeSync(file); } catch (e) { /* silent */ }
        }
      }
    });
  }

  /**
   * 写入文件内容
   */
  static writeFile(filePath: string, content: string): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Error) => void) => {
      let file: fileIo.File | undefined;
      try {
        file = fileIo.openSync(filePath,
          fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        const encoder = new util.TextEncoder();
        const buffer: Uint8Array = encoder.encodeInto(content);
        fileIo.writeSync(file.fd, buffer);
        resolve();
      } catch (err) {
        const msg = err instanceof Error ? (err as Error).message : String(err);
        reject(new Error('保存文件失败: ' + msg));
      } finally {
        if (file) {
          try { fileIo.closeSync(file); } catch (e) { /* 静默 */ }
        }
      }
    });
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

  /**
   * 检测文本中的换行符类型
   */
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