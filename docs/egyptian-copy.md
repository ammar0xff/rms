# Egyptian copy voice — what talks Masri, what stays MSA

The app speaks Egyptian Arabic to operators. Rule of thumb: **sentences talk
Masri, nouns stay MSA.**

## Rewrite (sentences operators read)

Empty states, error messages, hints, toasts/snackbars, dialog bodies,
section subtitles, instructional captions, freshness/sync/update notices,
confirmation prompts.

## Keep MSA (labels operators scan)

- Bottom bar, tabs, sidebar destinations, table column headers.
- Bare-noun screen titles (`التقارير`, `المخزون`, `الفروع`, `المطبخ`).
- Financial nouns: رصيد، خصم، ضريبة، فاتورة، جرد، تقرير، مخزون، تحصيل،
  إقرار، عهدة، مردودات (as a noun).
- Never touch: code identifiers, demo-auth email prefixes (`driver.@`…),
  tests, keys, interpolation, English strings, code comments.

## Mapping (MSA → Masri)

| MSA | Masri | Notes |
|---|---|---|
| لا يوجد / لا توجد / لا يتوفر | مفيش | `لا يوجد مخزن متاح` → `مفيش مخزن متاح` |
| لم يتم / لم يحدث | ما اتعملش / لسه | pick by tense |
| يجب | لازم | |
| يمكنك | تقدر | |
| يرجى / من فضلك | لو سمحت (or drop) | |
| تحقق من الشبكة | اتأكد من النت | الشبكة → النت in connectivity text |
| تعذّر | فشل / ما نفعش | `تعذّر الاتصال` → `الاتصال فشل` |
| الآن | دلوقتي | |
| اليوم | النهاردة | |
| أمس | امبارح | |
| بانتظار | مستني | states too: `مستني الاستلام` |
| قيد التحضير | بيتجهز | |
| قيد المزامنة | بيتزامن | |
| غير متزامن | ما اتزامنش | |
| متزامن | اتزامن | |
| تم التسليم | اتسلّم | |
| تم التقديم | اتقدّم | |
| مكتمل | خلصان | |
| في الانتظار | مستني | |
| تم + verb (تم حفظ/إنشاء/حذف/إغلاق/فتح/إرسال/تحديث) | اتحفظ/اتعمل/اتمسح/اتقفل/اتفتح/اتبعت/اتحدّث | passive → Egyptian passive |
| أُعيد / أُسندت (MSA passive) | رجّعنا / اتسندت | active where an actor exists |
| بنجاح | drop, or تمام | `تم الحفظ بنجاح` → `اتحفظ تمام` |
| عذرًا | معلش | |
| حدث خطأ / خطأ | حصلت مشكلة / فيه مشكلة | |
| حاول مرة أخرى / إعادة المحاولة | جرّب تاني | |
| هل أنت متأكد؟ | متأكد؟ | |
| نعم / لا (answers) | أيوه / لأ | |
| موافق | تمام / ماشي | |
| فارغ | فاضي | |
| وردية | شيفت | `وردية اليوم` → `شيفت النهاردة` |
| محلي (status) | على الجهاز | clearer than MSA محلي |
| نقدي | كاش | |
| بطاقة (payment) | فيزا | |
| استرداد | استرجاع | noun + verb |
| الطلب (in sentences) | الأوردر | keep طلب in tight table cells |
| التوصيل (chrome/title) | الدليفري | order-ref data untouched |
| سائق (role label) | طيار | |
| نقطة البيع (home label) | الكاشير | |
| داخل المطعم / سفري | صالة / تيك أواي | order types |
| تصدير CSV | نزّل CSV | |
| استدعاء السابقة | استرجع اللي فات | |
| تحديد كجاهز | علّم كجاهز | |
| إعادة طباعة | اطبع تاني | |
| تسجيل الدخول (title/button) | أهلاً بيك / ادخل | |
| خروج | اخرج | |
| مرحبًا | أهلاً | |
| يتطلب الإقرار مديرًا | الإقرار محتاج مدير | |
| الخادم | السيرفر | |

## Buttons (short imperatives → Masri imperative)

اختر→اختار، أضف→ضيف، احذف→امسح، عرض→شوف، إغلاق→اقفل، بدء→ابدأ،
إنهاء→خلّص، ابحث→دوّر، تحديث→حدّث، حفظ→احفظ، إلغاء→إلغاء (keep —
universal), تأكيد→أكّد.

When unsure, keep MSA. Shorter is better — every string must still fit
390px, and the responsive sweeps will fail the build on overflow.
