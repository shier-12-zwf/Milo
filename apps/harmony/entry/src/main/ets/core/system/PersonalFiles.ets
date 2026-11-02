import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { KVStorage } from '../data/KVStorage';
import { DiaryEntry } from '../model/Domain';
import { exportDiaryJson, exportDiaryMarkdown } from '../data/DiaryExport';
import { clearAvatarRecord } from './AvatarCleanup';

export class PersonalFiles {
  private context: common.UIAbilityContext;
  private storage: KVStorage;
  private uid: string;
  constructor(context: common.UIAbilityContext, storage: KVStorage, uid: string) {
    this.context = context; this.storage = storage; this.uid = uid;
  }
  private avatarKey(): string { return `milo.avatar.${this.uid}`; }
  avatar(): string { return this.storage.read(this.avatarKey()) ?? ''; }

  async chooseAvatar(): Promise<string> {
    const result = await new photoAccessHelper.PhotoViewPicker().select({
      MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1,
    });
    if (result.photoUris.length === 0) return this.avatar();
    const source = fs.openSync(result.photoUris[0], fs.OpenMode.READ_ONLY);
    const path = `${this.context.filesDir}/avatar-${Date.now()}.img`;
    try {
      if (fs.statSync(source.fd).size > 20 * 1024 * 1024) throw new Error('请选择小于 20 MB 的图片。');
      fs.copyFileSync(source.fd, path);
    } finally { fs.closeSync(source); }
    const previous = this.avatar();
    this.storage.write(this.avatarKey(), path);
    if (previous.startsWith(`${this.context.filesDir}/avatar-`)) {
      try { fs.unlinkSync(previous); } catch {}
    }
    return path;
  }

  resetAvatar(): void {
    clearAvatarRecord(this.storage, this.avatarKey(), this.context.filesDir, (path: string): void => {
      try { fs.unlinkSync(path); } catch (error) {
        // An already-removed file is a successful retry; permission/I/O errors
        // must leave the pointer and bubble up to the deletion coordinator.
        if ((error as BusinessError).code !== 13900002) throw new Error('头像文件清理未完成，请重试。');
      }
    });
  }

  async export(entries: DiaryEntry[], format: string): Promise<boolean> {
    const extension = format === 'json' ? 'json' : 'md';
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`MILO-${new Date().toISOString().slice(0, 10)}.${extension}`];
    const paths = await new picker.DocumentViewPicker(this.context).save(options);
    if (paths.length === 0) return false;
    const text = extension === 'json' ? exportDiaryJson(entries) : exportDiaryMarkdown(entries);
    const file = fs.openSync(paths[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const bytes = new util.TextEncoder().encodeInto(text);
      let offset = 0;
      while (offset < bytes.byteLength) {
        const written = fs.writeSync(file.fd, bytes.buffer.slice(offset));
        if (written <= 0) throw new Error('导出文件未完整写入。');
        offset += written;
      }
      fs.fsyncSync(file.fd);
    } finally { fs.closeSync(file); }
    return true;
  }
}
