# Распакованные скрипты из autounattend.xml

Это **справочный материал аудита**, не часть продукта. Файлы вынуты из `<File path="...">` внутри
`autounattend.xml` (этап specialize файла ответов) и лежат здесь, чтобы можно было читать их как обычный
текст, не разбирая 1100 строк XML.

**Их нельзя запускать.** Содержимое хранится в XML-экранированном виде: например, вместо `&` стоит `&amp;`,
вместо `<` — `&lt;`. Скрипты проекта эти файлы не используют — рабочая копия создаётся установщиком Windows
из самого XML при установке.

Имена файлов приведены к допустимым в Windows: исходные пути вида `C:\Windows\Setup\Scripts\X.ps1`
превращены в `Scripts_X.ps1` (двоеточие в имени файла недопустимо в Windows, из-за него падал checkout в CI).

Соответствие исходным путям:

| Файл здесь | Куда кладёт установщик |
|---|---|
| `Scripts_RemovePackages.ps1` | `C:\Windows\Setup\Scripts\RemovePackages.ps1` |
| `Scripts_RemoveCapabilities.ps1` | `C:\Windows\Setup\Scripts\RemoveCapabilities.ps1` |
| `Scripts_RemoveFeatures.ps1` | `C:\Windows\Setup\Scripts\RemoveFeatures.ps1` |
| `Scripts_Specialize.ps1` | `C:\Windows\Setup\Scripts\Specialize.ps1` |
| `Scripts_DefaultUser.ps1` | `C:\Windows\Setup\Scripts\DefaultUser.ps1` |
| `Scripts_UserOnce.ps1` | `C:\Windows\Setup\Scripts\UserOnce.ps1` |
| `Scripts_FirstLogon.ps1` | `C:\Windows\Setup\Scripts\FirstLogon.ps1` |
| `Scripts_unattend-01.ps1` | `C:\Windows\Setup\Scripts\unattend-01.ps1` (журнал включён, System logon) |
| `Scripts_unattend-02.ps1` | `C:\Windows\Setup\Scripts\unattend-02.ps1` (лоадер: качает репозиторий и запускает менеджер) |
| `Scripts_TaskbarLayoutModification.xml` | `C:\Windows\Setup\Scripts\TaskbarLayoutModification.xml` |
| `Scripts_UnlockStartLayout.xml` / `.vbs` | задачи планировщика: снятие блокировки меню «Пуск» |
| `Scripts_PauseWindowsUpdate.xml` | задача планировщика: пауза обновлений |
| `DefaultUser_LayoutModification.xml` | `C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml` |

Папка исключена из проверок в CI: файлы заведомо не являются синтаксически верным PowerShell из-за
XML-экранирования.
