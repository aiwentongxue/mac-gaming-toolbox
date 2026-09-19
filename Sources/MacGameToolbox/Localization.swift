import AppKit
import Combine
import Foundation
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

enum AppLanguage {
    enum Preference: String, CaseIterable, Identifiable {
        case system
        case simplifiedChinese
        case traditionalChinese
        case english
        case japanese
        case korean
        case german
        case french
        case spanish
        case portuguese

        var id: Self { self }
    }

    static let preferenceKey = "appLanguagePreference"

    static var preference: Preference {
        Preference(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .system
    }

    static var currentLanguage: Preference {
        switch preference {
        case .system:
            return systemLanguage
        default:
            return preference
        }
    }

    static var isChinese: Bool {
        switch currentLanguage {
        case .simplifiedChinese, .traditionalChinese:
            return true
        default:
            return false
        }
    }

    private static var systemLanguage: Preference {
        guard let identifier = Locale.preferredLanguages.first else { return .english }
        let locale = Locale(identifier: identifier)
        let languageCode = locale.language.languageCode?.identifier.lowercased()
        switch languageCode {
        case "zh":
            // macOS reports the script for entries such as zh-Hant-TW and zh-Hans-CN.
            return locale.language.script?.identifier.caseInsensitiveCompare("Hant") == .orderedSame
                ? .traditionalChinese
                : .simplifiedChinese
        case "ja": return .japanese
        case "ko": return .korean
        case "de": return .german
        case "fr": return .french
        case "es": return .spanish
        case "pt": return .portuguese
        default: return .english
        }
    }

    static func preferenceName(_ preference: Preference) -> String {
        switch preference {
        case .system: return text("跟随系统", "Follow System")
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .spanish: return "Español"
        case .portuguese: return "Português"
        }
    }

    static func text(_ chinese: String, _ english: String) -> String {
        let language = currentLanguage
        switch language {
        case .simplifiedChinese:
            return chinese
        case .english:
            return english
        case .system:
            // `currentLanguage` never returns .system, but keep this case future-safe.
            return english
        default:
            return translations[chinese]?[language] ?? english
        }
    }

    static func phase(_ phase: TaskPhase) -> String {
        switch phase {
        case .idle: text("空闲", "Idle")
        case .awaitingAuthorization: text("等待授权", "Awaiting authorization")
        case .running: text("进行中", "Running")
        case .succeeded: text("已完成", "Completed")
        case .failed: text("失败", "Failed")
        case .cancelled: text("已取消", "Cancelled")
        }
    }
}

private extension AppLanguage {
    /// Common interface labels are kept here so language changes take effect immediately,
    /// without requiring an app relaunch or a separate .strings bundle per language.
    static let translations: [String: [Preference: String]] = [
        "Mac游戏工具箱": [.traditionalChinese: "Mac 遊戲工具箱", .japanese: "Macゲームツールボックス", .korean: "Mac 게임 도구 상자", .german: "Mac-Spiele-Toolbox", .french: "Boîte à outils de jeux Mac", .spanish: "Caja de herramientas para juegos Mac", .portuguese: "Caixa de ferramentas de jogos para Mac"],
        "工具箱": [.traditionalChinese: "工具箱", .japanese: "ツールボックス", .korean: "도구 상자", .german: "Toolbox", .french: "Boîte à outils", .spanish: "Caja de herramientas", .portuguese: "Caixa de ferramentas"],
        "设置": [.traditionalChinese: "設定", .japanese: "設定", .korean: "설정", .german: "Einstellungen", .french: "Réglages", .spanish: "Configuración", .portuguese: "Ajustes"],
        "通用": [.traditionalChinese: "一般", .japanese: "一般", .korean: "일반", .german: "Allgemein", .french: "Général", .spanish: "General", .portuguese: "Geral"],
        "语言": [.traditionalChinese: "語言", .japanese: "言語", .korean: "언어", .german: "Sprache", .french: "Langue", .spanish: "Idioma", .portuguese: "Idioma"],
        "显示语言": [.traditionalChinese: "顯示語言", .japanese: "表示言語", .korean: "표시 언어", .german: "Anzeigesprache", .french: "Langue d’affichage", .spanish: "Idioma de visualización", .portuguese: "Idioma de exibição"],
        "跟随系统": [.traditionalChinese: "跟隨系統", .japanese: "システムに従う", .korean: "시스템 설정 따르기", .german: "Systemeinstellung verwenden", .french: "Suivre le système", .spanish: "Seguir al sistema", .portuguese: "Seguir o sistema"],
        "帮助": [.traditionalChinese: "輔助說明", .japanese: "ヘルプ", .korean: "도움말", .german: "Hilfe", .french: "Aide", .spanish: "Ayuda", .portuguese: "Ajuda"],
        "关于 Mac游戏工具箱": [.traditionalChinese: "關於 Mac 遊戲工具箱", .japanese: "Macゲームツールボックスについて", .korean: "Mac 게임 도구 상자 정보", .german: "Über Mac-Spiele-Toolbox", .french: "À propos de Boîte à outils de jeux Mac", .spanish: "Acerca de Caja de herramientas para juegos Mac", .portuguese: "Sobre Caixa de ferramentas de jogos para Mac"],
        "退出Mac游戏工具箱": [.traditionalChinese: "結束 Mac 遊戲工具箱", .japanese: "Macゲームツールボックスを終了", .korean: "Mac 게임 도구 상자 종료", .german: "Mac-Spiele-Toolbox beenden", .french: "Quitter Boîte à outils de jeux Mac", .spanish: "Salir de Caja de herramientas para juegos Mac", .portuguese: "Sair da Caixa de ferramentas de jogos para Mac"],
        "导出诊断日志": [.traditionalChinese: "輸出診斷日誌", .japanese: "診断ログを書き出す", .korean: "진단 로그 내보내기", .german: "Diagnoseprotokoll exportieren", .french: "Exporter les diagnostics", .spanish: "Exportar diagnósticos", .portuguese: "Exportar diagnósticos"],
        "修复核心功能": [.traditionalChinese: "修復核心功能", .japanese: "コア機能を修復", .korean: "핵심 기능 복구", .german: "Kernfunktionen reparieren", .french: "Réparer les fonctions principales", .spanish: "Reparar funciones principales", .portuguese: "Reparar funções principais"],
        "教程总导航": [.traditionalChinese: "教學總導航", .japanese: "チュートリアル一覧", .korean: "튜토리얼 허브", .german: "Tutorial-Übersicht", .french: "Hub des tutoriels", .spanish: "Centro de tutoriales", .portuguese: "Central de tutoriais"],
        "取消": [.traditionalChinese: "取消", .japanese: "キャンセル", .korean: "취소", .german: "Abbrechen", .french: "Annuler", .spanish: "Cancelar", .portuguese: "Cancelar"],
        "完成": [.traditionalChinese: "完成", .japanese: "完了", .korean: "완료", .german: "Fertig", .french: "Terminé", .spanish: "Listo", .portuguese: "Concluído"],
        "刷新": [.traditionalChinese: "重新整理", .japanese: "更新", .korean: "새로 고침", .german: "Aktualisieren", .french: "Actualiser", .spanish: "Actualizar", .portuguese: "Atualizar"],
        "删除": [.traditionalChinese: "刪除", .japanese: "削除", .korean: "삭제", .german: "Löschen", .french: "Supprimer", .spanish: "Eliminar", .portuguese: "Excluir"],
        "添加": [.traditionalChinese: "加入", .japanese: "追加", .korean: "추가", .german: "Hinzufügen", .french: "Ajouter", .spanish: "Añadir", .portuguese: "Adicionar"],
        "导入": [.traditionalChinese: "輸入", .japanese: "読み込む", .korean: "가져오기", .german: "Importieren", .french: "Importer", .spanish: "Importar", .portuguese: "Importar"],
        "选择": [.traditionalChinese: "選擇", .japanese: "選択", .korean: "선택", .german: "Auswählen", .french: "Choisir", .spanish: "Elegir", .portuguese: "Escolher"],
        "查看": [.traditionalChinese: "檢視", .japanese: "表示", .korean: "보기", .german: "Anzeigen", .french: "Afficher", .spanish: "Ver", .portuguese: "Ver"],
        "更新日志": [.traditionalChinese: "更新日誌", .japanese: "変更履歴", .korean: "변경 로그", .german: "Änderungsprotokoll", .french: "Journal des modifications", .spanish: "Registro de cambios", .portuguese: "Registro de alterações"],
        "导入壁纸": [.traditionalChinese: "輸入桌布", .japanese: "壁紙を読み込む", .korean: "배경화면 가져오기", .german: "Hintergrundbild importieren", .french: "Importer le fond d’écran", .spanish: "Importar fondo de pantalla", .portuguese: "Importar papel de parede"],
        "恢复默认": [.traditionalChinese: "回復預設", .japanese: "初期設定に戻す", .korean: "기본값 복원", .german: "Standard wiederherstellen", .french: "Rétablir les valeurs par défaut", .spanish: "Restablecer", .portuguese: "Restaurar padrão"],
        "一键清理": [.traditionalChinese: "一鍵清理", .japanese: "今すぐクリーンアップ", .korean: "지금 정리", .german: "Jetzt bereinigen", .french: "Nettoyer maintenant", .spanish: "Limpiar ahora", .portuguese: "Limpar agora"],
        "管理磁盘": [.traditionalChinese: "管理磁碟", .japanese: "ボリュームを管理", .korean: "볼륨 관리", .german: "Volumes verwalten", .french: "Gérer les volumes", .spanish: "Administrar volúmenes", .portuguese: "Gerenciar volumes"],
        "开始运行": [.traditionalChinese: "開始執行", .japanese: "開始", .korean: "시작", .german: "Starten", .french: "Démarrer", .spanish: "Iniciar", .portuguese: "Iniciar"],
        "目录": [.traditionalChinese: "目錄", .japanese: "場所", .korean: "위치", .german: "Speicherort", .french: "Emplacement", .spanish: "Ubicación", .portuguese: "Localização"],
        "常用进程优化": [.traditionalChinese: "常用程序最佳化", .japanese: "お気に入りプロセスを最適化", .korean: "즐겨찾는 프로세스 최적화", .german: "Favorisierte Prozesse optimieren", .french: "Optimiser les processus favoris", .spanish: "Optimizar procesos favoritos", .portuguese: "Otimizar processos favoritos"],
        "编辑常用进程": [.traditionalChinese: "編輯常用程序", .japanese: "お気に入りプロセスを編集", .korean: "즐겨찾는 프로세스 편집", .german: "Favorisierte Prozesse bearbeiten", .french: "Modifier les processus favoris", .spanish: "Editar procesos favoritos", .portuguese: "Editar processos favoritos"],
        "添加常用进程": [.traditionalChinese: "加入常用程序", .japanese: "お気に入りプロセスを追加", .korean: "즐겨찾는 프로세스 추가", .german: "Favorisierten Prozess hinzufügen", .french: "Ajouter un processus favori", .spanish: "Añadir proceso favorito", .portuguese: "Adicionar processo favorito"],
        "输入精确进程名": [.traditionalChinese: "輸入精確程序名稱", .japanese: "正確なプロセス名を入力", .korean: "정확한 프로세스 이름 입력", .german: "Exakten Prozessnamen eingeben", .french: "Saisir le nom exact du processus", .spanish: "Introducir nombre exacto del proceso", .portuguese: "Inserir nome exato do processo"],
        "尚未收藏常用进程": [.traditionalChinese: "尚未收藏常用程序", .japanese: "お気に入りプロセスはありません", .korean: "저장된 즐겨찾는 프로세스가 없습니다", .german: "Keine favorisierten Prozesse gespeichert", .french: "Aucun processus favori enregistré", .spanish: "No hay procesos favoritos guardados", .portuguese: "Nenhum processo favorito salvo"],
        "收藏进程": [.traditionalChinese: "收藏程序", .japanese: "プロセスをお気に入りに追加", .korean: "프로세스 즐겨찾기", .german: "Prozess favorisieren", .french: "Ajouter le processus aux favoris", .spanish: "Agregar proceso a favoritos", .portuguese: "Favoritar processo"],
        "取消收藏": [.traditionalChinese: "取消收藏", .japanese: "お気に入りから削除", .korean: "즐겨찾기 해제", .german: "Favorit entfernen", .french: "Retirer des favoris", .spanish: "Quitar de favoritos", .portuguese: "Remover dos favoritos"],
        "常用进程优化只会按完整且区分大小写的进程名进行搜索": [.traditionalChinese: "常用程序最佳化只會按完整且區分大小寫的程序名稱進行搜尋", .japanese: "お気に入りプロセスの最適化は、完全一致かつ大文字と小文字を区別したプロセス名のみを検索します", .korean: "즐겨찾는 프로세스 최적화는 완전 일치하고 대소문자를 구분하는 프로세스 이름만 검색합니다", .german: "Die Optimierung favorisierter Prozesse sucht nur nach vollständigen, groß- und kleinschreibungssensitiven Prozessnamen", .french: "L’optimisation des processus favoris recherche uniquement des noms de processus complets sensibles à la casse", .spanish: "La optimización de procesos favoritos solo busca nombres completos de proceso que distinguen mayúsculas", .portuguese: "A otimização de processos favoritos pesquisa apenas nomes completos de processo com distinção entre maiúsculas e minúsculas"],
        "正在优化常用进程": [.traditionalChinese: "正在最佳化常用程序", .japanese: "お気に入りプロセスを最適化中", .korean: "즐겨찾는 프로세스 최적화 중", .german: "Favorisierte Prozesse werden optimiert", .french: "Optimisation des processus favoris", .spanish: "Optimizando procesos favoritos", .portuguese: "Otimizando processos favoritos"],
        "未检测到收藏的常用进程": [.traditionalChinese: "未偵測到收藏的常用程序", .japanese: "保存したお気に入りプロセスは実行されていません", .korean: "저장된 즐겨찾는 프로세스가 실행 중이 아닙니다", .german: "Kein gespeicherter favorisierter Prozess wird ausgeführt", .french: "Aucun processus favori enregistré n’est en cours d’exécution", .spanish: "No se está ejecutando ningún proceso favorito guardado", .portuguese: "Nenhum processo favorito salvo está em execução"],
        "匹配的常用进程超过 64 个，请编辑常用进程后重试": [.traditionalChinese: "相符的常用程序超過 64 個，請編輯常用程序後重試", .japanese: "一致するお気に入りプロセスが64件を超えています。編集してから再試行してください", .korean: "일치하는 즐겨찾는 프로세스가 64개를 초과합니다. 편집 후 다시 시도하세요", .german: "Mehr als 64 favorisierte Prozesse stimmen überein. Bearbeiten Sie die Favoriten und versuchen Sie es erneut", .french: "Plus de 64 processus favoris correspondent. Modifiez les favoris puis réessayez", .spanish: "Coinciden más de 64 procesos favoritos. Edite los favoritos e inténtelo de nuevo", .portuguese: "Mais de 64 processos favoritos correspondem. Edite os favoritos e tente novamente"],
        "CrossOver进程": [.traditionalChinese: "CrossOver 程序", .japanese: "CrossOver プロセス", .korean: "CrossOver 프로세스", .german: "CrossOver-Prozesse", .french: "Processus CrossOver", .spanish: "Procesos de CrossOver", .portuguese: "Processos do CrossOver"],
        "手动选择进程": [.traditionalChinese: "手動選擇程序", .japanese: "プロセスを選択", .korean: "프로세스 선택", .german: "Prozesse auswählen", .french: "Sélectionner des processus", .spanish: "Seleccionar procesos", .portuguese: "Selecionar processos"],
        "恢复上次挂载": [.traditionalChinese: "回復上次掛載", .japanese: "前回のマウントを復元", .korean: "이전 마운트 복원", .german: "Letzte Einbindung wiederherstellen", .french: "Restaurer le dernier montage", .spanish: "Restaurar último montaje", .portuguese: "Restaurar última montagem"],
        "挂载到指定路径": [.traditionalChinese: "掛載到指定路徑", .japanese: "指定パスにマウント", .korean: "지정 경로에 마운트", .german: "Am angegebenen Pfad einbinden", .french: "Monter à l’emplacement indiqué", .spanish: "Montar en la ruta indicada", .portuguese: "Montar no caminho especificado"],
        "磁盘挂载": [.traditionalChinese: "磁碟掛載", .japanese: "ボリュームのマウント", .korean: "볼륨 마운트", .german: "Volume einbinden", .french: "Montage de volumes", .spanish: "Montaje de volúmenes", .portuguese: "Montagem de volumes"],
        "默认路径": [.traditionalChinese: "預設路徑", .japanese: "デフォルトのパス", .korean: "기본 경로", .german: "Standardpfade", .french: "Chemins par défaut", .spanish: "Rutas predeterminadas", .portuguese: "Caminhos padrão"],
        "可用磁盘": [.traditionalChinese: "可用磁碟", .japanese: "利用可能なボリューム", .korean: "사용 가능한 볼륨", .german: "Verfügbare Volumes", .french: "Volumes disponibles", .spanish: "Volúmenes disponibles", .portuguese: "Volumes disponíveis"],
        "恢复默认挂载": [.traditionalChinese: "回復預設掛載", .japanese: "標準のマウントに戻す", .korean: "기본 마운트 복원", .german: "Standard-Mount wiederherstellen", .french: "Montage par défaut", .spanish: "Restaurar montaje predeterminado", .portuguese: "Restaurar montagem padrão"],
        "全局启用": [.traditionalChinese: "全域啟用", .japanese: "全体で有効化", .korean: "전체 활성화", .german: "Global aktivieren", .french: "Activer globalement", .spanish: "Activar globalmente", .portuguese: "Ativar globalmente"],
        "切换模式": [.traditionalChinese: "切換模式", .japanese: "モードを切り替える", .korean: "모드 전환", .german: "Modus wechseln", .french: "Changer de mode", .spanish: "Cambiar modo", .portuguese: "Alternar modo"],
        "打开导航": [.traditionalChinese: "開啟導航", .japanese: "ハブを開く", .korean: "허브 열기", .german: "Übersicht öffnen", .french: "Ouvrir le hub", .spanish: "Abrir centro", .portuguese: "Abrir central"]
        ,"MetalHUD性能监视器": [.traditionalChinese: "MetalHUD 效能監視器", .japanese: "MetalHUD パフォーマンスモニター", .korean: "MetalHUD 성능 모니터", .german: "MetalHUD-Leistungsmonitor", .french: "Moniteur de performances MetalHUD", .spanish: "Monitor de rendimiento MetalHUD", .portuguese: "Monitor de desempenho MetalHUD"]
        ,"HoYoGames 启动帮助": [.traditionalChinese: "HoYoGames 啟動輔助", .japanese: "HoYoGames 起動アシスタント", .korean: "HoYoGames 실행 도우미", .german: "HoYoGames-Startassistent", .french: "Assistant de lancement HoYoGames", .spanish: "Asistente de inicio de HoYoGames", .portuguese: "Assistente de inicialização HoYoGames"]
        ,"提高进程优先级": [.traditionalChinese: "提高程序優先權", .japanese: "プロセスの優先度を上げる", .korean: "프로세스 우선순위 높이기", .german: "Prozesspriorität erhöhen", .french: "Augmenter la priorité du processus", .spanish: "Aumentar prioridad del proceso", .portuguese: "Aumentar a prioridade do processo"]
        ,"检测并提高游戏进程优先级": [.traditionalChinese: "偵測並提高遊戲程序優先權", .japanese: "ゲームプロセスを検出して優先度を上げる", .korean: "게임 프로세스를 감지하고 우선순위 높이기", .german: "Spielprozesse erkennen und ihre Priorität erhöhen", .french: "Détecter les processus de jeu et augmenter leur priorité", .spanish: "Detectar procesos de juego y aumentar su prioridad", .portuguese: "Detectar processos de jogos e aumentar sua prioridade"]
        ,"将磁盘挂载指定路径": [.traditionalChinese: "將磁碟掛載到指定路徑", .japanese: "ディスクを指定パスにマウント", .korean: "디스크를 지정 경로에 마운트", .german: "Datenträger am angegebenen Pfad einbinden", .french: "Monter un disque à un emplacement donné", .spanish: "Montar un disco en una ruta específica", .portuguese: "Montar um disco em um caminho especificado"]
        ,"缓存日志一键清理": [.traditionalChinese: "快取與日誌一鍵清理", .japanese: "キャッシュとログを一括クリーンアップ", .korean: "캐시 및 로그 원클릭 정리", .german: "Cache und Protokolle bereinigen", .french: "Nettoyage des caches et journaux", .spanish: "Limpieza de caché y registros", .portuguese: "Limpeza de cache e registros"]
        ,"切换到SteamDeck模式": [.traditionalChinese: "切換至 SteamDeck 模式", .japanese: "SteamDeck モードに切り替える", .korean: "SteamDeck 모드로 전환", .german: "In den SteamDeck-Modus wechseln", .french: "Passer en mode SteamDeck", .spanish: "Cambiar al modo SteamDeck", .portuguese: "Alternar para o modo SteamDeck"]
        ,"对单个 App 启用": [.traditionalChinese: "為單一 App 啟用", .japanese: "個別のアプリで有効化", .korean: "앱 하나에 활성화", .german: "Für eine App aktivieren", .french: "Activer pour une app", .spanish: "Activar para una app", .portuguese: "Ativar para um app"]
        ,"等待时间": [.traditionalChinese: "等待時間", .japanese: "待機時間", .korean: "대기 시간", .german: "Wartezeit", .french: "Temps d’attente", .spanish: "Tiempo de espera", .portuguese: "Tempo de espera"]
        ,"排除敏感文件": [.traditionalChinese: "排除敏感檔案", .japanese: "機密ファイルを除外", .korean: "민감한 파일 제외", .german: "Sensible Dateien ausschließen", .french: "Exclure les fichiers sensibles", .spanish: "Excluir archivos sensibles", .portuguese: "Excluir arquivos confidenciais"]
        ,"最近使用 MetalHUD 打开的 App": [.traditionalChinese: "最近使用 MetalHUD 開啟的 App", .japanese: "MetalHUD で最近開いたアプリ", .korean: "MetalHUD로 최근 연 앱", .german: "Kürzlich mit MetalHUD geöffnete Apps", .french: "Apps récemment ouvertes avec MetalHUD", .spanish: "Apps abiertas recientemente con MetalHUD", .portuguese: "Apps abertas recentemente com MetalHUD"]
        ,"其他 App": [.traditionalChinese: "其他 App", .japanese: "ほかのアプリ", .korean: "다른 앱", .german: "Andere App", .french: "Autre app", .spanish: "Otra app", .portuguese: "Outro app"]
        ,"搜索进程名称、目录或 PID": [.traditionalChinese: "搜尋程序名稱、目錄或 PID", .japanese: "プロセス名、場所、または PID を検索", .korean: "프로세스 이름, 위치 또는 PID 검색", .german: "Prozessname, Speicherort oder PID suchen", .french: "Rechercher un nom, emplacement ou PID de processus", .spanish: "Buscar nombre, ubicación o PID de proceso", .portuguese: "Pesquisar nome, localização ou PID do processo"]
        ,"提高优先级": [.traditionalChinese: "提高優先權", .japanese: "優先度を上げる", .korean: "우선순위 높이기", .german: "Priorität erhöhen", .french: "Augmenter la priorité", .spanish: "Aumentar prioridad", .portuguese: "Aumentar prioridade"]
        ,"保存预设": [.traditionalChinese: "儲存預設", .japanese: "プリセットを保存", .korean: "프리셋 저장", .german: "Voreinstellung speichern", .french: "Préréglage enregistrer", .spanish: "Guardar preajuste", .portuguese: "Salvar predefinição"]
        ,"浏览": [.traditionalChinese: "瀏覽", .japanese: "参照", .korean: "찾아보기", .german: "Durchsuchen", .french: "Parcourir", .spanish: "Examinar", .portuguese: "Procurar"]
        ,"开发者工具，可以查看游戏帧率等信息，也可以帮助你找到游戏异常的原因": [.traditionalChinese: "開發者工具，可查看遊戲幀率等資訊，也能協助找出遊戲異常原因", .japanese: "ゲームのフレームレートなどを確認し、問題の原因を探せる開発者ツール", .korean: "게임 프레임률 등을 확인하고 문제의 원인을 찾을 수 있는 개발자 도구", .german: "Entwicklertool zum Anzeigen der Bildrate und zur Diagnose von Spielproblemen", .french: "Outil de développement pour afficher la fréquence d’images et diagnostiquer les problèmes", .spanish: "Herramienta de desarrollo para ver la frecuencia de fotogramas y diagnosticar problemas", .portuguese: "Ferramenta de desenvolvimento para ver a taxa de quadros e diagnosticar problemas"]
        ,"此选项可以帮助你启动HoYoGames，点击“开始运行”后需要在指定时间内打开游戏": [.traditionalChinese: "此選項可協助啟動 HoYoGames；點擊「開始執行」後，請在指定時間內開啟遊戲", .japanese: "HoYoGames の起動を支援します。「開始」をクリックしたら、指定時間内にゲームを開いてください", .korean: "HoYoGames 실행을 돕습니다. 시작을 누른 후 지정된 시간 안에 게임을 여세요", .german: "Hilft beim Starten von HoYoGames. Öffnen Sie das Spiel nach „Start“ innerhalb der gewählten Zeit", .french: "Aide à lancer HoYoGames. Ouvrez le jeu dans le délai choisi après « Démarrer »", .spanish: "Ayuda a iniciar HoYoGames. Abre el juego dentro del tiempo seleccionado tras pulsar «Iniciar»", .portuguese: "Ajuda a iniciar o HoYoGames. Abra o jogo dentro do tempo selecionado após clicar em «Iniciar»"]
        ,"倒计时结束后不提升优先级": [.traditionalChinese: "倒數結束後不提高優先權", .japanese: "カウントダウン終了後に優先度を上げない", .korean: "카운트다운 후 우선순위를 높이지 않음", .german: "Priorität nach dem Countdown nicht erhöhen", .french: "Ne pas augmenter la priorité après le compte à rebours", .spanish: "No aumentar la prioridad al terminar la cuenta atrás", .portuguese: "Não aumentar a prioridade após a contagem regressiva"]
        ,"启动帮助选项": [.traditionalChinese: "啟動輔助選項", .japanese: "起動アシスタントのオプション", .korean: "실행 도우미 옵션", .german: "Optionen des Startassistenten", .french: "Options de l’assistant de lancement", .spanish: "Opciones del asistente de inicio", .portuguese: "Opções do assistente de inicialização"]
        ,"秒": [.traditionalChinese: "秒", .japanese: "秒", .korean: "초", .german: "Sek.", .french: "s", .spanish: "s", .portuguese: "s"]
        ,"此方法可自定义外接磁盘的挂载路径，可将部分原本不可放在外接磁盘的游戏资源转移到外接磁盘以节省内置磁盘储存空间": [.traditionalChinese: "此方法可自訂外接磁碟的掛載路徑，將部分原本無法放在外接磁碟的遊戲資源移轉到外接磁碟，以節省內置磁碟空間", .japanese: "外付けボリュームのマウント先を指定し、一部のゲームデータを移動して内蔵ストレージを節約できます", .korean: "외장 볼륨의 마운트 경로를 지정하고 일부 게임 리소스를 옮겨 내장 저장 공간을 절약합니다", .german: "Legt den Einbindungspfad externer Volumes fest und spart internen Speicher durch das Verschieben unterstützter Spieldaten", .french: "Personnalise le point de montage d’un volume externe et libère de l’espace interne en y déplaçant les données compatibles", .spanish: "Personaliza la ruta de montaje de un volumen externo y ahorra espacio interno moviendo recursos compatibles", .portuguese: "Personaliza o caminho de montagem de um volume externo e economiza espaço interno movendo recursos compatíveis"]
        ,"使用上下箭头调整首页选项框的顺序。": [.traditionalChinese: "使用上下箭頭調整首頁選項框的順序。", .japanese: "上下の矢印でダッシュボードカードの順序を変更します。", .korean: "위쪽 및 아래쪽 화살표로 대시보드 카드 순서를 변경합니다.", .german: "Mit den Pfeilen ändern Sie die Reihenfolge der Dashboard-Karten.", .french: "Utilisez les flèches pour modifier l’ordre des cartes du tableau de bord.", .spanish: "Usa las flechas para cambiar el orden de las tarjetas del panel.", .portuguese: "Use as setas para alterar a ordem dos cartões do painel."]
        ,"已显示": [.traditionalChinese: "已顯示", .japanese: "表示中", .korean: "표시됨", .german: "Angezeigt", .french: "Affichées", .spanish: "Mostradas", .portuguese: "Exibidos"]
        ,"可添加": [.traditionalChinese: "可加入", .japanese: "追加可能", .korean: "추가 가능", .german: "Verfügbar", .french: "Disponibles", .spanish: "Disponibles", .portuguese: "Disponíveis"]
        ,"上移": [.traditionalChinese: "上移", .japanese: "上へ移動", .korean: "위로 이동", .german: "Nach oben", .french: "Monter", .spanish: "Subir", .portuguese: "Mover para cima"]
        ,"下移": [.traditionalChinese: "下移", .japanese: "下へ移動", .korean: "아래로 이동", .german: "Nach unten", .french: "Descendre", .spanish: "Bajar", .portuguese: "Mover para baixo"]
        ,"为 CrossOver 容器选择 MetalHUD 预设": [.traditionalChinese: "為 CrossOver 容器選擇 MetalHUD 預設", .japanese: "CrossOver ボトル用の MetalHUD プリセットを選択", .korean: "CrossOver 보틀용 MetalHUD 프리셋 선택", .german: "MetalHUD-Voreinstellung für CrossOver-Bottle auswählen", .french: "Choisir un préréglage MetalHUD pour une bouteille CrossOver", .spanish: "Elegir un ajuste preestablecido de MetalHUD para un contenedor de CrossOver", .portuguese: "Escolher uma predefinição do MetalHUD para um bottle do CrossOver"]
        ,"为 iOS 游戏开启 MetalHUD": [.traditionalChinese: "為 iOS 遊戲啟用 MetalHUD", .japanese: "iOS ゲームで MetalHUD を有効化", .korean: "iOS 게임에서 MetalHUD 활성화", .german: "MetalHUD für ein iOS-Spiel aktivieren", .french: "Activer MetalHUD pour un jeu iOS", .spanish: "Activar MetalHUD para un juego de iOS", .portuguese: "Ativar o MetalHUD para um jogo iOS"]
        ,"关闭": [.traditionalChinese: "關閉", .japanese: "閉じる", .korean: "닫기", .german: "Schließen", .french: "Fermer", .spanish: "Cerrar", .portuguese: "Fechar"]
        ,"选择需要提高优先级的进程": [.traditionalChinese: "選擇需要提高優先權的程序", .japanese: "優先度を上げるプロセスを選択", .korean: "우선순위를 높일 프로세스 선택", .german: "Prozesse auswählen, deren Priorität erhöht werden soll", .french: "Choisissez les processus dont la priorité doit être augmentée", .spanish: "Elige los procesos cuya prioridad debe aumentarse", .portuguese: "Escolha os processos cuja prioridade deve ser aumentada"]
        ,"降低优先级": [.traditionalChinese: "降低優先權", .japanese: "優先度を下げる", .korean: "우선순위 낮추기", .german: "Priorität senken", .french: "Réduire la priorité", .spanish: "Reducir prioridad", .portuguese: "Reduzir prioridade"]
        ,"选择 CrossOver 容器": [.traditionalChinese: "選擇 CrossOver 容器", .japanese: "CrossOver ボトルを選択", .korean: "CrossOver 보틀 선택", .german: "CrossOver-Bottle auswählen", .french: "Choisir une bouteille CrossOver", .spanish: "Elegir un contenedor de CrossOver", .portuguese: "Escolher um bottle do CrossOver"]
        ,"仅显示同时包含 cxbottle.conf 与 drive_c 的容器。选择后再选取 MetalHUD 预设文件。": [.traditionalChinese: "僅顯示同時包含 cxbottle.conf 與 drive_c 的容器。選擇後再選取 MetalHUD 預設檔。", .japanese: "cxbottle.conf と drive_c の両方を含むボトルのみ表示します。選択後に MetalHUD プリセットを指定します。", .korean: "cxbottle.conf와 drive_c가 모두 있는 보틀만 표시합니다. 선택 후 MetalHUD 프리셋을 고릅니다.", .german: "Nur Bottles mit cxbottle.conf und drive_c werden angezeigt. Wählen Sie anschließend die MetalHUD-Voreinstellung.", .french: "Seules les bouteilles contenant cxbottle.conf et drive_c sont affichées. Choisissez ensuite le préréglage MetalHUD.", .spanish: "Solo se muestran contenedores con cxbottle.conf y drive_c. Después elige el ajuste preestablecido de MetalHUD.", .portuguese: "Apenas bottles com cxbottle.conf e drive_c são exibidos. Depois escolha a predefinição do MetalHUD."]
        ,"保存 MetalHUD 预设": [.traditionalChinese: "儲存 MetalHUD 預設", .japanese: "MetalHUD プリセットを保存", .korean: "MetalHUD 프리셋 저장", .german: "MetalHUD-Voreinstellung speichern", .french: "Enregistrer le préréglage MetalHUD", .spanish: "Guardar ajuste preestablecido de MetalHUD", .portuguese: "Salvar predefinição do MetalHUD"]
        ,"选项框编辑": [.traditionalChinese: "選項框編輯", .japanese: "カードを編集", .korean: "카드 편집", .german: "Karten bearbeiten", .french: "Modifier les cartes", .spanish: "Editar tarjetas", .portuguese: "Editar cartões"]
        ,"为 iOS 应用程序传入启动参数": [.traditionalChinese: "為 iOS 應用程式傳入啟動參數", .japanese: "iOS アプリの起動引数を設定", .korean: "iOS 앱 실행 인수 설정", .german: "Startargumente für iOS-App festlegen", .french: "Définir les arguments de lancement de l’app iOS", .spanish: "Establecer argumentos de inicio de la app de iOS", .portuguese: "Definir argumentos de inicialização do app iOS"]
        ,"iOS 应用程序启动参数": [.traditionalChinese: "iOS 應用程式啟動參數", .japanese: "iOS アプリの起動引数", .korean: "iOS 앱 실행 인수", .german: "Startargumente der iOS-App", .french: "Arguments de lancement de l’app iOS", .spanish: "Argumentos de inicio de la app de iOS", .portuguese: "Argumentos de inicialização do app iOS"]
        ,"iOS 设备": [.traditionalChinese: "iOS 裝置", .japanese: "iOS デバイス", .korean: "iOS 기기", .german: "iOS-Geräte", .french: "Appareils iOS", .spanish: "Dispositivos iOS", .portuguese: "Dispositivos iOS"]
        ,"搜索应用名称或包名": [.traditionalChinese: "搜尋應用程式名稱或套件名稱", .japanese: "アプリ名またはバンドルIDを検索", .korean: "앱 이름 또는 번들 ID 검색", .german: "App-Name oder Bundle-ID suchen", .french: "Rechercher le nom ou l’identifiant de l’app", .spanish: "Buscar nombre o ID del paquete", .portuguese: "Pesquisar nome ou ID do pacote"]
        ,"带 MetalHUD 启动": [.traditionalChinese: "帶 MetalHUD 啟動", .japanese: "MetalHUD を付けて起動", .korean: "MetalHUD로 실행", .german: "Mit MetalHUD starten", .french: "Lancer avec MetalHUD", .spanish: "Iniciar con MetalHUD", .portuguese: "Iniciar com MetalHUD"]
        ,"应用到容器": [.traditionalChinese: "套用到容器", .japanese: "ボトルに適用", .korean: "보틀에 적용", .german: "Auf Bottle anwenden", .french: "Appliquer à la bouteille", .spanish: "Aplicar al contenedor", .portuguese: "Aplicar ao bottle"]
        ,"取消并恢复 hosts": [.traditionalChinese: "取消並還原 hosts", .japanese: "キャンセルして hosts を復元", .korean: "취소하고 hosts 복원", .german: "Abbrechen und hosts wiederherstellen", .french: "Annuler et restaurer hosts", .spanish: "Cancelar y restaurar hosts", .portuguese: "Cancelar e restaurar hosts"]
        ,"取消置顶": [.traditionalChinese: "取消置頂", .japanese: "ピン留めを解除", .korean: "고정 해제", .german: "Loslösen", .french: "Désépingler", .spanish: "Desfijar", .portuguese: "Desafixar"]
        ,"保存": [.traditionalChinese: "儲存", .japanese: "保存", .korean: "저장", .german: "Sichern", .french: "Enregistrer", .spanish: "Guardar", .portuguese: "Salvar"]
        ,"内置": [.traditionalChinese: "內置", .japanese: "内蔵", .korean: "내장", .german: "Intern", .french: "Interne", .spanish: "Interno", .portuguese: "Interno"]
        ,"移除": [.traditionalChinese: "移除", .japanese: "削除", .korean: "제거", .german: "Entfernen", .french: "Supprimer", .spanish: "Quitar", .portuguese: "Remover"]
        ,"导出": [.traditionalChinese: "輸出", .japanese: "書き出す", .korean: "내보내기", .german: "Exportieren", .french: "Exporter", .spanish: "Exportar", .portuguese: "Exportar"]
        ,"更新": [.traditionalChinese: "更新", .japanese: "アップデート", .korean: "업데이트", .german: "Updates", .french: "Mises à jour", .spanish: "Actualizaciones", .portuguese: "Atualizações"]
        ,"前往更新": [.traditionalChinese: "前往更新", .japanese: "アップデートへ", .korean: "업데이트", .german: "Aktualisieren", .french: "Mettre à jour", .spanish: "Actualizar", .portuguese: "Atualizar"]
        ,"发现新版本": [.traditionalChinese: "發現新版本", .japanese: "新しいバージョンがあります", .korean: "새 버전 발견", .german: "Neue Version verfügbar", .french: "Nouvelle version disponible", .spanish: "Nueva versión disponible", .portuguese: "Nova versão disponível"]
        ,"暂不更新": [.traditionalChinese: "暫不更新", .japanese: "今は更新しない", .korean: "나중에 업데이트", .german: "Nicht jetzt", .french: "Pas maintenant", .spanish: "Ahora no", .portuguese: "Agora não"]
        ,"启动时检查更新": [.traditionalChinese: "啟動時檢查更新", .japanese: "起動時にアップデートを確認", .korean: "시작할 때 업데이트 확인", .german: "Beim Start nach Updates suchen", .french: "Rechercher les mises à jour au démarrage", .spanish: "Buscar actualizaciones al iniciar", .portuguese: "Verificar atualizações ao iniciar"]
        ,"内置 ClickFlow 更新至 1.0.1，改进组合宏手柄回放和设置": [.traditionalChinese: "內置 ClickFlow 更新至 1.0.1，改進組合巨集控制器播放與設定", .japanese: "内蔵 ClickFlow を 1.0.1 に更新し、複合マクロのコントローラー再生と設定を改善しました", .korean: "내장 ClickFlow를 1.0.1로 업데이트하고 조합 매크로의 컨트롤러 재생과 설정을 개선했습니다", .german: "Das integrierte ClickFlow wurde auf 1.0.1 aktualisiert und die Controller-Wiedergabe sowie Einstellungen für kombinierte Makros wurden verbessert", .french: "ClickFlow intégré a été mis à jour vers la version 1.0.1 avec une lecture des manettes et des réglages améliorés pour les macros combinées", .spanish: "ClickFlow integrado se actualizó a la versión 1.0.1 con mejoras en la reproducción de mando y los ajustes de las macros combinadas", .portuguese: "O ClickFlow integrado foi atualizado para a versão 1.0.1 com melhorias na reprodução do controle e nos ajustes das macros combinadas"]
        ,"新增 CrossOver Windows 游戏手柄集成，可将物理手柄与宏输入通过 XInput 代理传递给所选游戏": [.traditionalChinese: "新增 CrossOver Windows 遊戲控制器整合，可透過 XInput 代理將實體控制器與巨集輸入傳遞給所選遊戲", .japanese: "CrossOver の Windows ゲーム向けコントローラー統合を追加し、物理コントローラーとマクロ入力を XInput プロキシ経由で選択したゲームに渡せるようにしました", .korean: "CrossOver Windows 게임 컨트롤러 통합을 추가하여 실제 컨트롤러와 매크로 입력을 XInput 프록시를 통해 선택한 게임에 전달할 수 있습니다", .german: "Die CrossOver-Controller-Integration für Windows-Spiele leitet Eingaben von physischen Controllern und Makros über XInput-Proxys an das ausgewählte Spiel weiter", .french: "Ajout de l’intégration des manettes pour les jeux Windows dans CrossOver afin de transmettre les entrées de la manette physique et des macros au jeu sélectionné via des proxys XInput", .spanish: "Se añadió la integración de mandos para juegos de Windows en CrossOver, que transmite las entradas del mando físico y de las macros al juego seleccionado mediante proxies XInput", .portuguese: "Foi adicionada a integração de controles para jogos Windows no CrossOver, transmitindo entradas do controle físico e das macros ao jogo selecionado por proxies XInput"]
        ,"新增按游戏设置、诊断、安装、备份和安全恢复，并同时提供 x86 与 x64 代理资源": [.traditionalChinese: "新增按遊戲設定、診斷、安裝、備份與安全還原，並同時提供 x86 與 x64 代理資源", .japanese: "ゲーム単位の設定、診断、インストール、バックアップ、安全な復元を追加し、x86 と x64 の両方のプロキシリソースを収録しました", .korean: "게임별 설정, 진단, 설치, 백업 및 안전 복원을 추가하고 x86 및 x64 프록시 리소스를 모두 제공합니다", .german: "Spielspezifische Einrichtung, Diagnose, Installation, Sicherung und sichere Wiederherstellung wurden zusammen mit x86- und x64-Proxyressourcen hinzugefügt", .french: "Ajout de la configuration, du diagnostic, de l’installation, de la sauvegarde et de la restauration sécurisée par jeu, avec des ressources de proxy x86 et x64", .spanish: "Se añadieron configuración, diagnóstico, instalación, copia de seguridad y restauración segura por juego, junto con recursos proxy x86 y x64", .portuguese: "Foram adicionados configuração, diagnóstico, instalação, backup e restauração segura por jogo, além de recursos de proxy x86 e x64"]
        ,"纯手柄组合宏无需辅助功能权限即可播放，退出应用时会停止手柄直通并释放状态": [.traditionalChinese: "純控制器組合巨集無需輔助使用權限即可播放，結束應用程式時會停止控制器直通並釋放狀態", .japanese: "コントローラーのみの複合マクロはアクセシビリティ権限なしで再生でき、アプリ終了時にはコントローラーのパススルーを停止して状態を解放します", .korean: "컨트롤러 전용 조합 매크로는 손쉬운 사용 권한 없이 재생할 수 있으며 앱 종료 시 컨트롤러 패스스루를 중지하고 상태를 해제합니다", .german: "Reine Controller-Kombimakros können ohne Bedienungshilfen-Berechtigung abgespielt werden; beim Beenden werden Controller-Durchleitung und Zustand freigegeben", .french: "Les macros combinées utilisant uniquement la manette peuvent être lues sans autorisation d’accessibilité ; à la fermeture, le relais de la manette est arrêté et son état est libéré", .spanish: "Las macros combinadas que solo usan el mando pueden reproducirse sin permiso de Accesibilidad; al salir se detiene el paso directo del mando y se libera su estado", .portuguese: "Macros combinadas apenas de controle podem ser reproduzidas sem permissão de Acessibilidade; ao sair, a passagem direta do controle é interrompida e seu estado é liberado"]
        ,"修复组合宏页面的 CrossOver 手柄宏入口未固定在底部，以及二级页面标题与顶部切换器重叠的问题": [.traditionalChinese: "修復組合巨集頁面的 CrossOver 控制器巨集入口未固定在底部，以及次級頁面標題與頂部切換器重疊的問題", .japanese: "複合マクロ画面の CrossOver コントローラーマクロ入口が下部に固定されない問題と、サブページのタイトルが上部スイッチャーに重なる問題を修正しました", .korean: "조합 매크로 화면의 CrossOver 컨트롤러 매크로 항목이 하단에 고정되지 않는 문제와 하위 페이지 제목이 상단 전환기와 겹치는 문제를 수정했습니다", .german: "Der CrossOver-Controller-Makroeintrag bleibt nun am unteren Rand der Seite für kombinierte Makros, und der Titel der Unterseite überlappt nicht mehr den oberen Umschalter", .french: "Correction de l’entrée des macros de manette CrossOver qui ne restait pas en bas de la page des macros combinées et du titre de la page secondaire qui chevauchait le sélecteur supérieur", .spanish: "Se corrigió la entrada de macros de mando de CrossOver que no permanecía en la parte inferior de Macros combinadas y el título de la página secundaria que se superponía al selector superior", .portuguese: "Foi corrigida a entrada de macros de controle do CrossOver que não permanecia na parte inferior de Macros combinadas e o título da página secundária que se sobrepunha ao seletor superior"]
        ,"新增内置 ClickFlow，集成连点器、鼠标宏、组合宏和设置": [.traditionalChinese: "新增內置 ClickFlow，整合連點器、滑鼠巨集、組合巨集與設定", .japanese: "ClickFlow を内蔵し、オートクリッカー、マウスマクロ、複合マクロ、設定を統合しました", .korean: "ClickFlow를 내장하여 자동 클릭기, 마우스 매크로, 조합 매크로 및 설정을 통합했습니다", .german: "ClickFlow wurde mit Auto-Klicker, Mausmakros, kombinierten Makros und Einstellungen integriert", .french: "ClickFlow est désormais intégré avec clic automatique, macros de souris, macros combinées et réglages", .spanish: "Se ha integrado ClickFlow con autoclic, macros de ratón, macros combinadas y ajustes", .portuguese: "O ClickFlow foi integrado com clique automático, macros de mouse, macros combinadas e ajustes"]
        ,"ClickFlow 获得授权后可在工具箱页面继续响应全局快捷键，并保持播放、暂停和紧急停止能力": [.traditionalChinese: "ClickFlow 取得授權後可在工具箱頁面繼續回應全域快速鍵，並保留播放、暫停與緊急停止功能", .japanese: "許可後はツールボックス画面でも ClickFlow のグローバルショートカット、再生、一時停止、緊急停止を利用できます", .korean: "권한을 허용하면 도구 상자 화면에서도 ClickFlow 전역 단축키와 재생, 일시 정지, 긴급 중지를 사용할 수 있습니다", .german: "Nach der Freigabe bleiben globale ClickFlow-Kurzbefehle sowie Wiedergabe, Pause und Notstopp auf der Toolbox-Seite verfügbar", .french: "Après autorisation, les raccourcis globaux ClickFlow ainsi que la lecture, la pause et l’arrêt d’urgence restent disponibles dans la boîte à outils", .spanish: "Tras autorizarlo, los atajos globales de ClickFlow y las funciones de reproducción, pausa y parada de emergencia siguen disponibles en la caja de herramientas", .portuguese: "Após a autorização, os atalhos globais do ClickFlow e as funções de reprodução, pausa e parada de emergência continuam disponíveis na caixa de ferramentas"]
        ,"新增位于窗口标题栏中央的“工具箱 / ClickFlow”分段导航，并记住上次选择": [.traditionalChinese: "新增位於視窗標題列中央的「工具箱 / ClickFlow」分段導覽，並記住上次選擇", .japanese: "ウインドウのタイトルバー中央に、前回の選択を記憶する「ツールボックス / ClickFlow」セグメントナビゲーションを追加しました", .korean: "창 제목 표시줄 중앙에 마지막 선택을 기억하는 ‘도구 상자 / ClickFlow’ 분할 탐색을 추가했습니다", .german: "Eine zentrierte segmentierte Navigation für Toolbox und ClickFlow in der Titelleiste merkt sich die letzte Auswahl", .french: "Une navigation segmentée Boîte à outils / ClickFlow centrée dans la barre de titre mémorise le dernier choix", .spanish: "Se añadió una navegación segmentada Caja de herramientas / ClickFlow centrada en la barra de título que recuerda la última selección", .portuguese: "Foi adicionada uma navegação segmentada Caixa de ferramentas / ClickFlow centralizada na barra de título que memoriza a última seleção"]
        ,"集成版 ClickFlow 使用独立偏好和宏目录，不显示额外菜单栏图标，也不会读取或修改独立版数据": [.traditionalChinese: "整合版 ClickFlow 使用獨立偏好設定與巨集目錄，不顯示額外選單列圖示，也不會讀取或修改獨立版資料", .japanese: "統合版 ClickFlow は独立した設定とマクロ保存先を使用し、追加のメニューバーアイコンを表示せず、単体版のデータを読み書きしません", .korean: "통합 ClickFlow는 별도의 환경설정과 매크로 폴더를 사용하며 추가 메뉴 막대 아이콘을 표시하지 않고 독립 실행형 데이터를 읽거나 수정하지 않습니다", .german: "Das integrierte ClickFlow verwendet getrennte Einstellungen und Makroordner, zeigt kein zusätzliches Menüleistensymbol und greift nicht auf Daten der eigenständigen Version zu", .french: "Le ClickFlow intégré utilise des préférences et un dossier de macros distincts, n’ajoute aucune icône de barre des menus et ne lit ni ne modifie les données de la version autonome", .spanish: "ClickFlow integrado usa preferencias y una carpeta de macros independientes, no añade icono a la barra de menús y no lee ni modifica los datos de la versión independiente", .portuguese: "O ClickFlow integrado usa preferências e uma pasta de macros separadas, não adiciona ícone à barra de menus e não lê nem modifica os dados da versão independente"]
        ,"ClickFlow 页面接入九种语言，并提供集成版权限和首次使用说明": [.traditionalChinese: "ClickFlow 頁面支援九種語言，並提供整合版權限與首次使用說明", .japanese: "ClickFlow 画面を9言語に対応し、統合版向けの権限案内と初回使用時の説明を追加しました", .korean: "ClickFlow 화면을 9개 언어로 제공하고 통합 버전의 권한 안내와 최초 사용 설명을 추가했습니다", .german: "Die ClickFlow-Seiten unterstützen neun Sprachen und enthalten Berechtigungshinweise sowie einen Hinweis zur ersten Verwendung", .french: "Les pages ClickFlow prennent en charge neuf langues et proposent des indications d’autorisation ainsi qu’un avis de première utilisation", .spanish: "Las páginas de ClickFlow admiten nueve idiomas e incluyen indicaciones de permisos y un aviso de primer uso", .portuguese: "As páginas do ClickFlow oferecem suporte a nove idiomas e incluem orientações de permissão e um aviso de primeiro uso"]
        ,"修复从 ClickFlow 返回工具箱时，标题栏按钮可见但鼠标点击无响应的问题": [.traditionalChinese: "修復從 ClickFlow 返回工具箱時，標題列按鈕可見但滑鼠點按無回應的問題", .japanese: "ClickFlow からツールボックスに戻る際、タイトルバーのボタンが表示されていてもマウスクリックに反応しない問題を修正しました", .korean: "ClickFlow에서 도구 상자로 돌아갈 때 제목 표시줄 버튼이 보이지만 마우스 클릭에 반응하지 않던 문제를 수정했습니다", .german: "Ein Problem wurde behoben, bei dem die sichtbare Toolbox-Schaltfläche in der Titelleiste nach dem Öffnen von ClickFlow nicht auf Mausklicks reagierte", .french: "Correction d’un problème où le bouton Boîte à outils visible dans la barre de titre ne répondait plus aux clics après l’ouverture de ClickFlow", .spanish: "Se corrigió un problema por el que el botón visible Caja de herramientas de la barra de título no respondía al ratón después de abrir ClickFlow", .portuguese: "Foi corrigido um problema em que o botão visível Caixa de ferramentas na barra de título não respondia aos cliques do mouse após abrir o ClickFlow"]
    ]
}

@inline(__always)
func tr(_ chinese: String, _ english: String) -> String {
    AppLanguage.text(chinese, english)
}

@MainActor
final class LocalizationController: ObservableObject {
    @Published private(set) var preference = AppLanguage.preference
    @Published private(set) var refreshToken = UUID()

    func setPreference(_ preference: AppLanguage.Preference) {
        guard self.preference != preference else { return }
        self.preference = preference
        UserDefaults.standard.set(preference.rawValue, forKey: AppLanguage.preferenceKey)
        refreshToken = UUID()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var localization: LocalizationController
    @AppStorage(UpdateCheckPreference.key) private var automaticallyCheckForUpdates = true

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label(tr("通用", "General"), systemImage: "gearshape") }
        }
        .frame(width: 760, height: 520)
        .background(WindowTitleConfigurator(title: tr("设置", "Settings")))
    }

    private var generalSettings: some View {
        VStack {
            Form {
                Section {
                    Picker(tr("显示语言", "Display language"), selection: Binding(
                        get: { localization.preference },
                        set: { localization.setPreference($0) }
                    )) {
                        ForEach(AppLanguage.Preference.allCases) { preference in
                            Text(AppLanguage.preferenceName(preference)).tag(preference)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 320)
                } header: {
                    Text(tr("语言", "Language"))
                } footer: {
                    Text(tr("默认跟随 macOS 系统语言；选择语言后会立即应用，并在下次启动时保留。", "By default, the app follows the macOS language. Your selected language applies immediately and is remembered for future launches."))
                }

                Section {
                    Toggle(tr("启动时检查更新", "Check for updates at launch"), isOn: $automaticallyCheckForUpdates)
                } header: {
                    Text(tr("更新", "Updates"))
                } footer: {
                    Text(tr("默认开启。每次打开 Mac游戏工具箱时静默检查 GitHub Releases；仅发现新版本时才会提示。", "Enabled by default. Mac Game Toolbox silently checks GitHub Releases every time it opens and only notifies you when a newer version is available."))
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 76)
            .padding(.vertical, 32)
            Spacer(minLength: 0)
        }
    }
}

private struct WindowTitleConfigurator: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.title = title }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.title = title }
    }
}
