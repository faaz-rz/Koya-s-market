// Client taxonomy. Specific product rules precede old broad subcategories.
// No matching rule may silently fall back to Grocery & Staples.
import { createHash } from 'node:crypto';

export function categoryId(key) {
  const bytes = createHash('sha256').update(`koyas-client-category:${key}`).digest().subarray(0,16);
  bytes[6] = (bytes[6] & 15) | 80; bytes[8] = (bytes[8] & 63) | 128;
  const h = bytes.toString('hex');
  return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}

export function categoryForProduct(product) {
  const raw = product.billingName.toUpperCase().replace(/\s+/g, ' ').trim();
  const name = product.name.toUpperCase();
  const text = `${raw} ${name}`;
  const sub = product.subcategory;
  const inSub = (...values) => values.includes(sub);
  const has = (pattern) => pattern.test(text);

  if (has(/\bNEON\s*71\b/)) return 'general';
  if (raw === 'CUPS ASHIRWAD') return 'pooja';
  if (has(/\b(?:KAJAL|EYETEX|EYETX)\b/)) return 'body-care';
  if (has(/\b(?:RAT POISON|TOILET CLEANER)\b/)) return 'household';
  if (has(/\b(?:BABY|BBY|KIDS|PEDIASURE|GRIPE WATER|LAL TAIL)\b/)) return 'kids-care';
  if (has(/\b(?:VIM|EXO|PRIL|SABEENA)\b/)) return 'household';
  if (has(/\b(?:COMFORT|COMFT|SOFT TOUCH|SOFTTOUCH|REVIVE|CRISP)\b/)) return 'fabric-care';
  if (has(/\b(?:BUTTER ?MILK|LASSI|BADAM MILK|CONDENSED MILK)\b/)) return 'dairy';
  if (has(/\bKINDER JOY\b/)) return 'chocolates';
  if (has(/\b(?:HAJMOLA|ENO|ORSL)\b/)) return 'health';
  if (has(/\bMTR BADAM\b/)) return 'beverages';
  if (has(/\b(?:PINK|GREEN|ORANGE|KESAR[IY]?|YELLOW|LEMON|RED|FOOD)\s*(?:FOOD\s*)?COL[OU]+R\b|\bESSEN[CS]E/)
      && !has(/\b(?:HAIR|HOLI|POOJA|GODREJ|GARNIER)\b/)) return 'food-colour';
  if (has(/\b(?:KEWRA WATER|CARAMEL COLOUR)\b/)) return 'food-colour';
  if (has(/\b(?:KESAR[IY]?|KESRI)\s+YELLOW\b/)) return 'food-colour';
  if (inSub('Baking Ingredients') && has(/\b(?:LEMON YELLOW|ORANGE RED)\b/)) return 'food-colour';

  if (inSub('Pooja Supplies','Pooja Oil','Agarbathi & Incense','Candles','Camphor')) {
    if (raw === 'IMLLY') return 'spices';
    return 'pooja';
  }
  if (inSub('Cooking Oil','Cooking Oils')) return 'cooking-oils';
  if (inSub('Ghee')) return 'ghee';
  if (inSub('Ice Cream')) return 'ice-creams';
  if (inSub('Milk Powder','Paneer','Dairy Products','Curd','Butter','Condensed Milk','Milk','Cheese','Cream','Milk Products','Eggs')) return 'dairy';
  if (inSub('Baby Care','Child Care','Child Nutrition')) return 'kids-care';
  if (inSub('Tea & Coffee')) return 'tea-coffee';
  if (inSub('Pain Relief')) return 'pain-relief';
  if (inSub('Laundry Powder','Laundry Bar','Laundry Liquid')) return 'detergents';
  if (inSub('Pest Control','Dishwashing','Air Fresheners','Surface & Toilet Cleaners','Floor Cleaners','Cleaning Tools','Shoe Care','Cleaning & Laundry')) return 'household';
  if (inSub('Biscuits')) return 'biscuits';
  if (inSub('Chocolate & Confectionery')) return 'chocolates';
  if (inSub('Papad')) return 'papads';
  if (inSub('Pickles & Chutneys')) return 'pickles';
  if (inSub('Jam & Spreads','Honey')) return 'spreads';
  if (inSub('Sauces & Condiments','Sauces, Pickles & Canned Foods')) {
    return has(/\bJAM\b/) ? 'spreads' : 'sauces';
  }
  if (inSub('Canned Foods')) return has(/\bTOMATO\b/) ? 'sauces' : 'baking';
  if (inSub('Oats','Breakfast Cereals','Soup')) return 'breakfast';
  if (inSub('Noodles','Noodles, Pasta & Vermicelli','Pasta & Vermicelli')) {
    return has(/\b(?:MAGGI CUBES|MASALA|MSLA|MASLA)\b/) ? 'masala-box' : 'pasta';
  }
  if (inSub('Baking Ingredients')) return 'baking';
  if (inSub('Bread & Bakery','Cakes & Bakery','Chips & Savouries','Sweets & Confectionery','Indian Sweets','Fresh Snacks')) return 'snacks';
  if (inSub('Ready-to-Cook')) {
    if (has(/\b(?:RAVA|RAWA)\b/)) return 'grains';
    return has(/\b(?:GULAB|JAMUN|JMN)\b/) ? 'baking' : 'breakfast';
  }
  if (inSub('Nutrition & Energy Drinks','Squash & Syrups','Soft Drinks','Water & Traditional Drinks')) return 'beverages';
  if (inSub('First Aid & Antiseptics','Digestive & Rehydration','Digestive & Traditional Wellness','Sanitizers','Sugar Substitutes')) return 'health';
  if (inSub('Disposables & Tableware','Bags & Covers','Household Utility','Stationery','Cloth & Fabric','Stationery & Tools','Cards & Gifts','Batteries & Electrical','Matches & Lighters','Bags & Carriers')) return 'general';
  if (inSub('Vegetables')) return 'fresh';
  if (inSub('Shampoo','Perfume & Deodorant','Talcum Powder','Oral Care','Bath Soap','Body Lotion','Shaving & Grooming','Body Wash','Face Wash','Face Cream','Moisturiser','Hair Conditioner','Skin Cream','Hair Oil','Hair Removal','Hair Colour','Lip Care','Henna','Skin Care','Hair Care','Sun Care','Feminine Hygiene','Feminine Care','Cosmetics','Bath & Body','Hand Wash','Skin, Hair & Grooming','Skin & Body Care','Hair Styling','Mouth Freshener')) return 'body-care';

  // Remaining entries are food/loose groceries, including old misclassifications.
  if (has(/\b(?:GARAM)\s+(?:MASALA|MASLA|MSLA)/)) return 'garam-masalas';
  if (has(/\b(?:PICKLE|CHUTNE?Y|CHUTNY)\b/)) return 'pickles';
  if (has(/\b(?:SAUCE|SAUCES|SUS|KETCHUP|VINEGAR)\b/)) return 'sauces';
  if (has(/\b(?:BREAD CRUM|PANKO|TUT[TIY ]*FR[UIT ]+|BAKING|COCOA|COCO PDR)\b/)) return 'baking';
  if (has(/\b(?:SUGAR|JAGGERY|JAGIRY|GUD|SALT|NAMAK|NMK|MISRI)\b/)) return 'salt-sugar';
  if (raw === 'W SODA') return 'detergents';
  if (raw === 'E SODA') return 'baking';
  if (has(/\b(?:KARAKAYALU|PATHA|RALA)\b/)) return 'health';
  if (raw === 'REETA') return 'body-care';
  if (raw === 'LESSON') return 'fresh';
  if (has(/\b(?:BASMAT[IY]|BASMATHI)\b/) ||
      (has(/\bINDIA ?GATE\b|\bABIDA\b/) && !has(/\b(?:SONA|JEERA RICE)\b/))) return 'basmati';
  if (has(/\b(?:ATTA|FLOUR|MAIDA|BESAN|RICE POWDER)\b/)) return 'atta';
  if (has(/\b(?:BADAM|ALMOND|KAJU|CASHEW|AKH?ROOT|AKHROT|WALNUT|COPRA|DRY FRUIT[S]?|CHIRONGI|PALLY)\b/) || inSub('Dry Fruits & Nuts')) return 'dry-fruits';
  if (has(/\b(?:RAVA|RAWA|SOOJI|SUJI|SABUDANA|WHEAT|BARLEY|JOO|HEERA|RICE)\b/)) return 'grains';
  if (has(/\b(?:MOONG|MASOOR|RAJMA|UDATH?|UDAD|TUWAR|TOOR|LOB[IY]+A|KULTI|BATANA|CHANA|DAL|MDAL|MSRDAL|CHDAL|GDAL|UDAL|TDAL|PDAL|MNG|PUTTANA)\b/)) return 'dal';
  if (has(/\b(?:JAWARI|JOWAR|JOV|RAAGI|RAGI|BAJRA|KORALU|AND?AKORALU|ARIKALU|UDALU|SHAMALU|KORABIYAM|BAGAR)\b/) || inSub('Millets')) return 'millets';
  if (has(/\b(?:SAMIYA|PENNE|PENNY|VERMICELLI|PASTA)\b/) && !has(/\b(?:MASALA|MASLA|MSLA)\b/)) return 'pasta';
  if (has(/\b(?:SOYA|MILMAKER|MEAL MAKER)\b/) || inSub('Soya Products')) return 'grains';
  if (inSub('Rice')) return 'grains';
  if (has(/\bDALCHINI\b/)) return 'spices';
  if (inSub('Whole Spices','Spices & Seasoning','Masala & Spice Mixes')) {
    if (has(/\b(?:GARAM)\b/)) return 'garam-masalas';
    if (has(/\b(?:MASALA|MASLA|MSLA|BIRYANI|BIRIYANI|BHAJI|SAMBAR|RASAM|RESAM|TANDOORI|KITCHEN KING|PANI PURI|JALJIRA|JAL JEERA|IDLI KARAM)\b/) &&
        !has(/\b(?:TIKHA|THIKA|TIKHALAL|MIRCHI|CHILLI|CHILY|HALDI|TURMERIC|CORIANDER|CUMIN|ZEERA|AMCHUR|PEPPER|GINGER)\b/)) return 'masala-box';
    return 'spices';
  }
  if (inSub('Cooking Ingredients')) return 'baking';
  if (inSub('Atta & Flour','Atta, Flour & Rava')) return 'atta';
  if (inSub('Loose Grocery') && has(/\b(?:SOMP|SAUNF|SABJA|DANIYA|HALDI|ELACHI|KASKAS|TILL|METHI|KABAB CHINI|KARBOOZ)\b/)) return 'spices';
  if (inSub('Packed Grocery') && has(/\b(?:TURMERIC|HP)\b/)) return 'spices';
  throw new Error(`Category needs explicit review: ${raw} / ${sub}`);
}
