export const code = async ({ context, policy, attributes, prompts }) => {
  const listings = context.listings.map(l => ({ sku_product_id: l.sku_product_id, store_name: l.store_name,
    product_info: l.product_info, title: l.title, description: l.description,
    rich_content_text: l.rich_content_text, rich_content_configured: l.rich_content_configured,
    primary_image_url: l.primary_image_url, search_terms: l.search_terms,
    attributes: l.attributes.map(a => ({ id: a.id, name: a.name, current_values: a.current_values })) }));
  return { prompt: prompts.rule + '\n\n' + prompts.text_contract,
    text: JSON.stringify({ sku_code: context.sku_code, grade: context.grade, stage: context.stage, as_of: context.as_of, policy, attribute_diagnosis: attributes, listings }),
    files: listings.filter(l => l.primary_image_url).map(l => ({ file: l.primary_image_url })) };
};
