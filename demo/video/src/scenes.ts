// Сценарий демо-видео. Время — в секундах записи (timeline.json после prep),
// прямоугольники — в точках экрана [x, y, w, h], куда смотрит «камера».

export type Rect = [number, number, number, number];
type Src = 'en' | 'ru1' | 'ru2' | 'ru3';

export type Scene = {
  src: Src;
  from: number;
  to: number;
  speed?: number;
  // Вырезанные куски записи [начало, конец] — на их месте короткое растворение.
  // Так убираем анимации Stage Manager (окна «влетают» с низкой частотой кадров).
  cuts?: [number, number][];
  cam: [number, Rect][];
  // Заплатка: кусок кадра из другой записи поверх этой (rect — в точках экрана).
  patch?: {src: Src; file: string; rect: Rect};
  title: string;
  sub: string;
};

export type Script = {
  lang: 'en' | 'ru';
  intro: {title: string; tagline: string; badge: string};
  outro: {title: string; line: string};
  scenes: Scene[];
};

const finder: Rect = [190, 180, 820, 460];
const finderMenu: Rect = [190, 180, 930, 620];
const finderMenuTall: Rect = [190, 180, 940, 700];
const progress: Rect = [735, 95, 540, 200];

export const en: Script = {
  lang: 'en',
  intro: {
    title: '7-Zip for macOS',
    tagline: 'The classic Windows 7-Zip interface — right in Finder',
    badge: 'Unofficial front end · MIT',
  },
  outro: {title: 'github.com/eluz1ve/7zip-mac', line: 'Free · Open source · Native Swift'},
  scenes: [
    {
      src: 'en', from: 3.7, to: 7.95,
      cam: [[3.7, finder], [6.4, finderMenu]],
      title: 'Right-click → 7-Zip',
      sub: 'The familiar 7-Zip submenu, right inside Finder',
    },
    {
      src: 'en', from: 8.29, to: 12.95,
      cam: [[8.29, [748, 26, 760, 548]], [12.95, [770, 50, 720, 510]]],
      title: 'Add to Archive',
      sub: 'Format, level, method, dictionary, solid block, threads, volumes, encryption',
    },
    {
      src: 'en', from: 13.1, to: 20.7, speed: 2.5,
      cam: [[13.1, progress], [20.7, [748, 104, 515, 180]]],
      title: 'Progress you control',
      sub: 'Current file, elapsed time, Pause and Cancel',
    },
    {
      src: 'en', from: 36.6, to: 40.25,
      cam: [[36.6, finder], [38.0, finderMenuTall]],
      title: 'Extract your way',
      sub: 'Extract files…, Extract Here, Extract to “folder/”, Test archive',
    },
    {
      src: 'en', from: 40.6, to: 43.95, cuts: [[42.65, 43.45]],
      cam: [[40.6, [745, 26, 615, 322]], [42.65, [755, 34, 600, 310]], [43.45, finder]],
      title: 'Extract dialog',
      sub: 'Destination, subfolder, path mode, overwrite rules, password',
    },
    {
      src: 'en', from: 47.6, to: 53.95, speed: 1.2, cuts: [[51.1, 51.65], [52.75, 53.3]],
      cam: [[47.6, finder], [49.3, finderMenu], [51.1, finderMenu], [51.65, progress], [52.75, progress], [53.3, finder]],
      title: 'One-click archives',
      sub: 'Add to “name.7z” or “name.zip” — no dialogs, no questions',
    },
    {
      // Заканчиваем до клика по «Install new version…»: после него окно уходит в Stage Manager.
      src: 'en', from: 57.3, to: 59.4, speed: 0.8,
      cam: [[57.3, [745, 25, 540, 395]], [59.4, [755, 32, 520, 380]]],
      title: 'Drag & drop window',
      sub: 'Drop files to compress or archives to extract · install new 7-Zip releases',
    },
  ],
};

export const ru: Script = {
  lang: 'ru',
  intro: {
    title: '7-Zip для macOS',
    tagline: 'Классический интерфейс 7-Zip из Windows — прямо в Finder',
    badge: 'Неофициальная оболочка · MIT',
  },
  outro: {title: 'github.com/eluz1ve/7zip-mac', line: 'Бесплатно · Открытый код · Нативный Swift'},
  scenes: [
    {
      src: 'ru1', from: 4.1, to: 8.2,
      cam: [[4.1, finder], [7.0, finderMenu]],
      title: 'ПКМ → 7-Zip',
      sub: 'Привычное подменю 7-Zip прямо в контекстном меню Finder',
    },
    {
      src: 'ru1', from: 30.5, to: 35.2,
      cam: [[30.5, [188, 218, 762, 552]], [35.2, [205, 236, 730, 520]]],
      title: 'Добавить к архиву',
      sub: 'Формат, уровень, метод, словарь, блок, потоки, тома, шифрование',
    },
    {
      // В этой записи верх окна прогресса не попал в кадр (область начиналась с y = 120).
      // Окно стояло там же, где в записи ru2, — берём недостающую полоску оттуда.
      src: 'ru1', from: 35.7, to: 43.8, speed: 2.5,
      patch: {src: 'ru2', file: 'k00060.png', rect: [735, 90, 540, 30.7]},
      cam: [[35.7, progress], [43.8, [748, 104, 515, 180]]],
      title: 'Прогресс под контролем',
      sub: 'Текущий файл, прошедшее время, пауза и отмена',
    },
    {
      src: 'ru2', from: 2.75, to: 7.66, cuts: [[5.95, 6.85]],
      cam: [[2.75, finder], [4.6, finderMenuTall], [5.95, finderMenuTall], [6.85, finder]],
      title: 'Распаковка как в Windows',
      sub: 'Распаковать…, Распаковать здесь, Распаковать в «папку/», Тестировать',
    },
    {
      src: 'ru2', from: 8.0, to: 14.0, speed: 1.2, cuts: [[10.75, 11.09], [12.8, 13.3]],
      cam: [[8.0, finder], [9.6, finderMenu], [10.75, finderMenu], [11.09, progress], [12.8, progress], [13.3, finder]],
      title: 'Архив в один клик',
      sub: 'Добавить к «имя.7z» или «имя.zip» — без лишних окон',
    },
    {
      // Заканчиваем до клика по «Установить новую версию…»: после него окно уходит в Stage Manager.
      src: 'ru3', from: 1.1, to: 3.2, speed: 0.8,
      cam: [[1.1, [635, 25, 540, 395]], [3.2, [645, 32, 520, 380]]],
      title: 'Окно для перетаскивания',
      sub: 'Файлы — сжать, архивы — распаковать · установка новых версий 7-Zip',
    },
  ],
};

export const FPS = 30;
export const INTRO = 90;
export const OUTRO = 110;
export const OVERLAP = 12;
export const CUT_FADE = 8; // кадров на растворение в месте вырезанного куска

/** Куски записи, которые попадают в сцену. */
export const segmentsOf = (s: Scene): [number, number][] => {
  const segments: [number, number][] = [];
  let start = s.from;
  for (const [a, b] of s.cuts ?? []) {
    segments.push([start, a]);
    start = b;
  }
  segments.push([start, s.to]);
  return segments;
};

export const sceneFrames = (s: Scene) =>
  Math.round((segmentsOf(s).reduce((sum, [a, b]) => sum + b - a, 0) / (s.speed ?? 1)) * FPS);

/** Кадр, с которого начинается каждая сцена. */
export const sceneStarts = (script: Script) => {
  let start = INTRO - OVERLAP;
  return script.scenes.map((s) => {
    const from = start;
    start += sceneFrames(s) - OVERLAP;
    return from;
  });
};

export const totalFrames = (script: Script) =>
  INTRO + script.scenes.reduce((sum, s) => sum + sceneFrames(s) - OVERLAP, 0) + OUTRO;
