export const code = async ({ context, policy, prompts }) => {
  const listings = context.listings.map(l => ({ sku_product_id: l.sku_product_id, store_name: l.store_name,
    category_id: l.category_id, type_id: l.type_id, product_info: l.product_info,
    title: l.title, description: l.description, rich_content_text: l.rich_content_text,
    attributes: l.attributes.filter(a => ![4180, 4191, 11254, 9048, 12141, 22390, 8789, 8790, 21837, 21841, 21845, 22232, 22273, 23249, 23536, 23673].includes(a.id))
  }));
  return { prompt: prompts.rule + '\n\n' + prompts.attributes_contract,
    text: JSON.stringify({ sku_code: context.sku_code, grade: context.grade, stage: context.stage, as_of: context.as_of, policy, listings }) };
};
